# frozen_string_literal: true

module Gitlab
  module DuoWorkflow
    # Rebuilds a checkpoint's channel_values from incremental checkpoint blobs.
    # Each blob is a per-step delta (zlib-compressed JSON) for one (channel,
    # version); step_action carries the reducer signal -- a compaction replaces,
    # anything else appends. Pass blobs from a single ancestor chain (see
    # Ai::DuoWorkflows::Workflow#accumulated_blobs_for); off-chain blobs derive
    # from a different base and must not be mixed in.
    class ChannelValuesReconstructor
      include ::Gitlab::Utils::StrongMemoize

      COMPACTION = 'compaction'
      CONVERSATION = 'conversation'
      USER_MESSAGE = 'user'
      MESSAGE_ID = 'message_id'

      CorruptBlobError = Class.new(StandardError)

      # Decode a single blob's `data` (zlib-compressed JSON) to its Ruby value.
      # Exposed so callers that need just one blob (e.g. the tail of a channel)
      # can decode without instantiating a full reconstruction. Corruption isn't
      # expected (our gateway writes valid zlib JSON); raise rather than skip, so
      # a bad blob fails the read instead of returning inconsistent values.
      def self.decode(data)
        ::Gitlab::Json.safe_parse(Zlib::Inflate.inflate(data))
      rescue Zlib::Error, JSON::ParserError
        raise CorruptBlobError, 'Failed to decode checkpoint blob'
      end

      def initialize(blobs)
        @blobs = blobs
      end

      def channel_values
        blobs_by_channel.keys.index_with { |channel| fold(channel) }
      end

      # Build one channel's FULL history for display. Unlike #channel_values, which
      # anchors at the last compaction to rebuild agent state, this keeps every
      # conversation delta. From a mid-stream compaction snapshot it takes only the
      # entries not already in the history (see #unseen_entries): a restart re-seed
      # repeats known entries and adds nothing, while a compaction's summary card is
      # new and is kept. Only the earliest snapshot seeds the base. Pass blobs from
      # the full ancestor chain across all groups (Workflow#history_blobs_for).
      #
      # `ancestry` maps thread_ts -> parent_ts for that chain; every entry is stamped
      # with the checkpoint that introduced it (see #stamp).
      def channel_history(channel, ancestry, alternatives)
        # Prefer the conversation delta: it stays a delta even when the snapshot is
        # trimmed, so it never depends on the snapshot lining up with the fold.
        ordered_blobs_for(channel, prefer: CONVERSATION).reduce(nil) do |history, blob|
          if blob.step_action == COMPACTION && !history.nil?
            # Stamp only the new entries: the rest of the snapshot is dropped, and a
            # snapshot is the largest blob we read.
            added = unseen_entries(history, decode(blob.data))
            added.empty? ? history : history.concat(stamp(added, blob, ancestry, alternatives))
          else
            append(history, stamp(decode(blob.data), blob, ancestry, alternatives))
          end
        end
      end

      # Every value a channel took over the session, oldest first, so plan and status
      # changes stay visible instead of collapsing to a single value. Pass blobs from the
      # full ancestor chain across all groups (Workflow#full_history_blobs).
      #
      # Three shapes share this path, told apart by each decoded value rather than by the
      # channel, because a channel can start nil before it holds a list or a dict:
      #
      # - A list records each change as a delta, so a mid-stream compaction mostly repeats
      #   entries the deltas already carry. We keep only the entries it adds (see
      #   #unseen_entries), which is what the compaction-triggering step wrote.
      # - A dict snapshot is the full replacement the gateway writes for a `plan` step edit
      #   or a `last_human_input` key-set change. Keeping it would re-record the whole
      #   channel per edit, so the trace reports appends only.
      # - A scalar (status, goal) has no delta form -- the gateway writes every value as a
      #   full replacement -- so each blob is a real transition, bar one that repeats the
      #   value before it, which is a group re-seed rather than a change.
      def channel_changes(channel)
        # Prefer the conversation delta: a colliding compaction carries the whole channel,
        # so the delta is the more precise record of that version's change.
        ordered = ordered_blobs_for(channel, prefer: CONVERSATION)
        dict = false

        ordered.each_with_index.each_with_object([]) do |(blob, index), changes|
          snapshot = blob.step_action == COMPACTION && index > 0
          # A dict snapshot is dropped whatever it holds, and each one is as large as the
          # whole channel, so skip it before decoding.
          next if snapshot && dict

          value = decode(blob.data)

          case value
          when Array
            changes.concat(snapshot ? unseen_entries(changes, value) : value)
          when Hash
            dict = true
            next if snapshot

            changes.push(value)
          else
            changes.push(value) if changes.empty? || changes.last != value
          end
        end
      end

      # thread_ts -> the value a scalar channel held at that checkpoint. A scalar blob
      # carries the whole value, so there is nothing to fold; the work is picking one
      # row per checkpoint. Prefer the compaction.
      def scalar_values_by_thread_ts(channel)
        ordered_blobs_for(channel, prefer: COMPACTION)
          .to_h { |blob| [blob.thread_ts, decode(blob.data)] }
      end

      private

      # Anchor at the last compaction so the fold is O(deltas since it), not
      # O(chain length); safe only for a single ancestor chain (see #initialize).
      # Prefer the compaction: it carries the full value, so anchoring on it keeps
      # the fold short.
      def fold(channel)
        ordered = ordered_blobs_for(channel, prefer: COMPACTION)

        last_compaction = ordered.rindex { |blob| blob.step_action == COMPACTION }
        ordered = ordered.drop(last_compaction) if last_compaction

        ordered.reduce(nil) { |value, blob| apply(value, blob) }
      end

      # Blobs come in chain order (id order, see Workflow#accumulated_blobs_for), not
      # version order, because version numbers can repeat after a compaction resets the
      # writer's counter. group_by keeps each version at its first occurrence, so no sort.
      def ordered_blobs_for(channel, prefer:)
        # Dedup by thread_ts and version together, not version alone. A version can repeat
        # legitimately across thread groups, and grouping by version alone would drop it.
        blobs_by_channel.fetch(channel, [])
          .group_by { |blob| [blob.thread_ts, blob.version] }
          .values
          # A force_rewrite can store both a delta and a compaction under the same version.
          # `prefer` picks the winning step_action, so the result never depends on insertion
          # order (https://gitlab.com/gitlab-org/gitlab/-/issues/604371).
          .map { |rows| rows.find { |blob| blob.step_action == prefer } || rows.first }
      end

      # Memoized: one group_by(&:channel) pass covers all channels, not a rescan per channel.
      def blobs_by_channel
        @blobs.group_by(&:channel)
      end
      strong_memoize_attr :blobs_by_channel

      # A compaction replaces the running value; anything else appends.
      def apply(value, blob)
        delta = decode(blob.data)
        return delta if blob.step_action == COMPACTION

        append(value, delta)
      end

      # Snapshot entries not yet in `history`, the messages collected so far. A snapshot
      # may repeat the whole log (a restart re-seed) or hold only the summary card and
      # its own step's entries (a trimmed log), so match by message_id, not by prefix.
      # The compaction-triggering step writes no conversation delta of its own
      # (https://gitlab.com/gitlab-org/gitlab/-/issues/619495), so this is the only
      # place its entries can come from.
      def unseen_entries(history, snapshot)
        return [] unless history.is_a?(Array) && snapshot.is_a?(Array)

        seen_ids = history.filter_map { |entry| entry[MESSAGE_ID] if entry.is_a?(Hash) }.to_set

        snapshot.reject do |entry|
          id = entry[MESSAGE_ID] if entry.is_a?(Hash)
          id ? seen_ids.include?(id) : history.any? { |seen| same_entry?(seen, entry) }
        end
      end

      # #stamp adds keys to the accumulated entries, so match on the snapshot's own
      # fields rather than comparing the entries whole.
      def same_entry?(entry, other)
        return other.all? { |key, field| entry[key] == field } if entry.is_a?(Hash) && other.is_a?(Hash)

        entry == other
      end

      # Append `delta` onto the running `value` in place. Shared by #fold (agent
      # state) and #channel_history (display) so both grow lists identically.
      def append(value, delta)
        case delta
        when Array
          # concat (not +) so folding k appends is O(k), not O(k^2); delta is
          # freshly decoded, so it never aliases the compaction snapshot.
          value ? value.concat(delta) : delta
        when Hash
          # dict-of-list channel: append each key's tail to the accumulated list.
          return delta unless value.is_a?(Hash)

          delta.each do |key, tail|
            if tail.is_a?(Array)
              (value[key] ||= []).concat(tail)
            else
              value[key] = tail
            end
          end
          value
        else
          delta
        end
      end

      # Stamp each message with the checkpoint that introduced it: the blob's own
      # thread_ts and that checkpoint's parent_ts -- the point a client forks from.
      # A user message anchors its turn, so it also carries the alternative count.
      def stamp(value, blob, ancestry, alternatives)
        return value unless value.is_a?(Array)

        value.each do |entry|
          next unless entry.is_a?(Hash)

          entry['thread_ts'] = blob.thread_ts
          entry['parent_ts'] = ancestry[blob.thread_ts]
          next unless entry['message_type'] == USER_MESSAGE

          entry['alternative_count'] = alternatives.fetch(blob.thread_ts, 0)
        end
      end

      def decode(data)
        self.class.decode(data)
      end
    end
  end
end
