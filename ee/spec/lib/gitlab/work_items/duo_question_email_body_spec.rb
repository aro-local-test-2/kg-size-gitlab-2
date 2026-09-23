# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::WorkItems::DuoQuestionEmailBody, feature_category: :team_planning do
  describe '.rewrite' do
    let(:flow_service_account_id) { 42 }

    before do
      allow(::Ai::Catalog::ItemConsumer).to receive(:for_service_account)
        .with(flow_service_account_id).and_return(instance_double(ActiveRecord::Relation, exists?: true))
    end

    def flow_note(body)
      instance_double(Note, note: body, author_id: flow_service_account_id)
    end

    def rewrite(body, format: :html)
      described_class.rewrite(flow_note(body), format: format)
    end

    def fenced(payload)
      "Prose above.\n\n```json:duo-question\n#{payload}\n```"
    end

    def payload(type:, **attributes)
      fenced({ type: type }.merge(attributes).to_json)
    end

    def closed(**attributes)
      payload(type: 'closed', **attributes)
    end

    def labelled(count)
      Array.new(count) { |i| { id: "o#{i}", label: "Option #{i}" } }
    end

    def one_answer
      s_('WorkItemDuoQuestion|Choose one of these options, or answer in your own words:')
    end

    def many_answers
      s_('WorkItemDuoQuestion|Choose one or more of these options, or answer in your own words:')
    end

    it 'replaces a single-select payload with an introduced bullet list' do
      body = closed(
        question: 'Where should the limit live?',
        multiple: false,
        options: [
          { id: 'shell', label: 'In gitlab-shell', description: 'Closest to the connection.', recommended: true },
          { id: 'api', label: 'In the internal API' }
        ]
      )

      expect(rewrite(body)).to eq(<<~MD.rstrip)
        Prose above.

        Choose one of these options, or answer in your own words:

        - **In gitlab\\-shell** (Recommended): Closest to the connection\\.
        - **In the internal API**
      MD
    end

    it 'replaces a legacy marker with a list marking the 1-based recommended index' do
      body = %(Prose above.\n\n<!-- duo:options ["Redis", "In memory"] duo:recommended 2 -->)

      expect(rewrite(body)).to eq(<<~MD.rstrip)
        Prose above.

        Choose one of these options, or answer in your own words:

        - **Redis**
        - **In memory** (Recommended)
      MD
    end

    it 'rewrites every payload in a body carrying more than one' do
      body = [
        closed(options: [{ id: 'a', label: 'First' }]),
        closed(multiple: true, options: [{ id: 'b', label: 'Second' }])
      ].join("\n\n")

      result = rewrite(body)

      expect(result).to include('- **First**').and include('- **Second**')
      expect(result).not_to include('json:duo-question')
    end

    context 'with a renderable payload' do
      where(:case_name, :body, :expected) do
        [
          ['a multi-select fence',
            lazy do
              closed(multiple: true, options: [
                { id: 'a', label: 'Push', recommended: true },
                { id: 'b', label: 'Pull', recommended: true },
                { id: 'c', label: 'Tags' }
              ])
            end,
            lazy { "#{many_answers}\n\n- **Push** (Recommended)\n- **Pull** (Recommended)\n- **Tags**" }],
          ['a marker carrying duo:multiple',
            %(Prose above.\n\n<!-- duo:options ["Production", "Staging"] duo:recommended 1 duo:multiple -->),
            lazy { "#{many_answers}\n\n- **Production** (Recommended)\n- **Staging**" }],
          ['options right at the limit the work item UI renders',
            lazy { closed(options: labelled(described_class::MAX_OPTIONS)) },
            lazy { one_answer }]
        ]
      end

      with_them do
        it 'renders the options under the instruction matching the number of answers' do
          expect(rewrite(body)).to include(expected)
        end
      end
    end

    context 'when the payload has nothing worth listing' do
      where(:case_name, :body) do
        [
          ['an open question carries no options', lazy { payload(type: 'open', question: 'What rate?') }],
          ['a closed question has an empty option list', lazy { closed(options: []) }],
          ['options is not an array', lazy { closed(options: 'nope') }],
          ['the payload is not an object', lazy { fenced('"just a string"') }],
          ['the JSON is malformed', lazy { fenced('{"type": "closed", "options": [') }],
          ['every option is missing a label', lazy { closed(options: [{ id: 'a' }]) }],
          ['the only label spans several lines, which the card rejects',
            lazy { closed(options: [{ id: 'a', label: "Wrapped\nlabel" }]) }],
          ['there are more options than the work item UI renders',
            lazy { closed(options: labelled(described_class::MAX_OPTIONS + 1)) }],
          ['the options as written exceed the limit even though only one is usable',
            lazy do
              closed(options: [
                { id: 'usable', label: 'The only labelled option' },
                *Array.new(described_class::MAX_OPTIONS) { |i| { id: "o#{i}" } }
              ])
            end]
        ]
      end

      with_them do
        it 'removes the payload and leaves the prose' do
          expect(rewrite(body)).to eq('Prose above.')
        end
      end
    end

    context 'when building the plain text part' do
      # Nothing renders Markdown on that path, so escaping would only show the
      # reader backslashes that nothing downstream consumes.
      it 'leaves the label and description as the reader should see them' do
        body = closed(options: [
          { id: 'a', label: 'In gitlab-shell', description: 'Closest to the connection.', recommended: true }
        ])

        expect(rewrite(body, format: :text)).to eq(<<~MD.rstrip)
          Prose above.

          #{one_answer}

          - **In gitlab-shell** (Recommended): Closest to the connection.
        MD
      end

      it 'still escapes the same payload for the HTML part' do
        body = closed(options: [{ id: 'a', label: 'In gitlab-shell' }])

        expect(rewrite(body, format: :html)).to include('In gitlab\\-shell')
        expect(rewrite(body, format: :text)).to include('- **In gitlab-shell**')
      end

      it 'does not turn a model authored link into active Markdown on either part' do
        body = closed(options: [{ id: 'a', label: '[Click here](https://evil.test)' }])

        expect(rewrite(body, format: :html)).not_to include('](')
        expect(rewrite(body, format: :text)).to include('[Click here](https://evil.test)')
      end
    end

    context 'with values at the work item UI limits' do
      where(:case_name, :option, :expected, :unexpected) do
        [
          ['a label at the limit',
            lazy { { id: 'a', label: 'a' * described_class::MAX_LABEL_LENGTH } },
            lazy { 'a' * described_class::MAX_LABEL_LENGTH }, nil],
          ['a label over the limit',
            lazy { { id: 'a', label: 'a' * (described_class::MAX_LABEL_LENGTH + 1) } },
            'Prose above.', one_answer],
          ['a description over the limit',
            lazy do
              { id: 'a', label: 'Keep me', description: 'b' * (described_class::MAX_DESCRIPTION_LENGTH + 1) }
            end,
            lazy { 'b' * described_class::MAX_DESCRIPTION_LENGTH },
            lazy { 'b' * (described_class::MAX_DESCRIPTION_LENGTH + 1) }]
        ]
      end

      with_them do
        it 'matches the UI behavior' do
          result = rewrite(closed(options: [option]))

          expect(result).to include(expected)
          expect(result).not_to include(unexpected) if unexpected
        end
      end
    end

    it 'escapes model-authored Markdown in labels and descriptions', :aggregate_failures do
      options = [
        { id: 'link', label: '[Click](https://evil.test)' },
        { id: 'image', label: '![Beacon](https://evil.test/x.png)' },
        { id: 'emphasis', label: 'Bold** and **more' },
        { id: 'reference', label: 'Closes #1' },
        { id: 'code', label: '`rm -rf /`', description: 'See [here](https://evil.test)' }
      ]

      result = rewrite(closed(options: options))

      ['](https://evil.test)', 'Bold** and **more', 'Closes #1', '`rm -rf /`'].each do |markdown|
        expect(result).not_to include(markdown)
      end
    end

    context 'when the note was not authored by a flow service account' do
      let(:other_author_id) { 99 }

      before do
        allow(::Ai::Catalog::ItemConsumer).to receive(:for_service_account)
          .with(other_author_id).and_return(instance_double(ActiveRecord::Relation, exists?: false))
      end

      it 'leaves a fabricated payload exactly as it was written' do
        body = closed(options: [{ id: 'a', label: 'Approve the spend', recommended: true }])
        note = instance_double(Note, note: body, author_id: other_author_id)

        expect(described_class.rewrite(note)).to eq(body)
      end
    end

    context 'when the body carries no payload' do
      where(:case_name, :body) do
        [
          ['nil', nil],
          ['an empty string', ''],
          ['whitespace only', "  \n  "],
          ['prose with a trailing newline', "@root A plain comment.\n\nWith a second paragraph.\n"],
          ['prose merely mentioning the fence language', "See the json:duo-question block on the other note.\n"]
        ]
      end

      with_them do
        it 'returns the body byte-identical' do
          expect(rewrite(body)).to eq(body)
        end
      end

      it 'skips the catalog query without a payload hint' do
        note = instance_double(Note, note: 'An ordinary comment.')

        expect(::Ai::Catalog::ItemConsumer).not_to receive(:for_service_account)
        expect(described_class.rewrite(note)).to eq(note.note)
      end
    end
  end
end
