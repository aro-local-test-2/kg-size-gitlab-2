# frozen_string_literal: true

# The whole-policy schema and the single-rule schema duplicate the `risk_severity` branch by
# design, so both include these examples. That keeps the two in lockstep: if one schema's branch
# drifts from the other, that schema's own spec fails.
#
# An includer embeds `rule` in whatever document its schema validates, and defines
# `validation_result` over that document plus `denied_pointer`, the JSON pointer to the first
# `denied` entry. That pointer is deliberately not defaulted: it shifts with the embedding, so a
# future includer that forgets it fails loudly instead of asserting someone else's path.
RSpec.shared_examples 'a risk_severity rule schema' do
  using RSpec::Parameterized::TableSyntax

  let(:rule) do
    {
      type: 'risk_severity',
      denied: [{ severity: 'critical', threshold: 0 }, { severity: 'high', threshold: 10 }],
      exceptions: [{ purl: 'pkg:npm/my-internal-lib' }, { id: 'CVE-2020-8203' }]
    }
  end

  def expect_errors_to_include(expected_error)
    expect(validation_result["errors"].pluck("error")).to include expected_error
  end

  specify { expect(validation_result["valid"]).to be true }

  context 'without exceptions' do
    before do
      rule.delete(:exceptions)
    end

    specify { expect(validation_result["valid"]).to be true }
  end

  # Review asked whether risk_severity supports CVE exclusions like the `vulnerability` rule does.
  # It does, through the shared rule-level `exceptions` array rather than a key of its own. These
  # run against both schemas, so they also prove the risk_severity branch does not narrow them.
  context 'with an accepted exceptions array' do
    where(:case_name, :exceptions) do
      'CVE identifiers only' | [{ id: 'CVE-2020-8203' }, { id: 'CVE-2021-23337' }]
      'a PURL only'          | [{ purl: 'pkg:npm/my-internal-lib' }]
      'both kinds together'  | [{ purl: 'pkg:npm/my-internal-lib' }, { id: 'CVE-2020-8203' }]
    end

    with_them do
      before do
        rule[:exceptions] = exceptions
      end

      specify { expect(validation_result["valid"]).to be true }
    end
  end

  context 'with a rejected exceptions array' do
    where(:case_name, :exceptions) do
      'an entry naming neither a purl nor an id' | [{}]
      'an entry using an unrecognised key'       | [{ cve: 'CVE-2020-8203' }]
    end

    with_them do
      before do
        rule[:exceptions] = exceptions
      end

      specify { expect(validation_result["valid"]).to be false }
    end
  end

  context 'with an accepted denied array' do
    where(:case_name, :denied) do
      'a critical entry'       | [{ severity: 'critical', threshold: 1 }]
      'a high entry'           | [{ severity: 'high', threshold: 1 }]
      'a medium entry'         | [{ severity: 'medium', threshold: 1 }]
      'a low entry'            | [{ severity: 'low', threshold: 1 }]
      'a threshold of zero'    | [{ severity: 'low', threshold: 0 }]
      'one entry per severity' | [{ severity: 'critical', threshold: 0 }, { severity: 'high', threshold: 10 },
        { severity: 'medium', threshold: 25 }, { severity: 'low', threshold: 100 }]
    end

    with_them do
      before do
        rule[:denied] = denied
      end

      specify { expect(validation_result["valid"]).to be true }
    end
  end

  context 'with a rejected denied array' do
    # The two same-severity rows are why this is a per-severity `contains` + `maxContains: 1`
    # rather than `uniqueItems`: `uniqueItems` only dedups structurally identical entries, so it
    # would accept two `high` entries that differ by threshold.
    where(:case_name, :denied) do
      'the same severity twice'      | [{ severity: 'high', threshold: 5 }, { severity: 'high', threshold: 9 }]
      'same severity and threshold'  | [{ severity: 'low', threshold: 3 }, { severity: 'low', threshold: 3 }]
      'an unknown severity'          | [{ severity: 'unknown', threshold: 1 }]
      'an info severity'             | [{ severity: 'info', threshold: 1 }]
      'an uppercase severity'        | [{ severity: 'CRITICAL', threshold: 1 }]
      'a negative threshold'         | [{ severity: 'high', threshold: -1 }]
      'a non-integer threshold'      | [{ severity: 'high', threshold: 'ten' }]
      'an additional property'       | [{ severity: 'high', threshold: 5, mode: 'block' }]
      'an empty array'               | []
      'more entries than severities' | [{ severity: 'critical', threshold: 0 },
        { severity: 'high', threshold: 1 }, { severity: 'medium', threshold: 2 },
        { severity: 'low', threshold: 3 }, { severity: 'low', threshold: 4 }]
    end

    with_them do
      before do
        rule[:denied] = denied
      end

      specify { expect(validation_result["valid"]).to be false }
    end
  end

  context 'with a missing threshold' do
    before do
      rule[:denied] = [{ severity: 'high' }]
    end

    specify 'is invalid', :aggregate_failures do
      expect(validation_result["valid"]).to be false
      expect_errors_to_include("object at `#{denied_pointer}` is missing required properties: threshold")
    end
  end

  context 'with a missing severity' do
    before do
      rule[:denied] = [{ threshold: 5 }]
    end

    specify 'is invalid', :aggregate_failures do
      expect(validation_result["valid"]).to be false
      expect_errors_to_include("object at `#{denied_pointer}` is missing required properties: severity")
    end
  end

  context 'with allowed instead of denied' do
    let(:rule) { { type: 'risk_severity', allowed: [{ severity: 'high', threshold: 10 }] } }

    specify { expect(validation_result["valid"]).to be false }
  end

  context 'with both denied and allowed' do
    let(:rule) do
      {
        type: 'risk_severity',
        denied: [{ severity: 'high', threshold: 10 }],
        allowed: [{ severity: 'low', threshold: 100 }]
      }
    end

    specify { expect(validation_result["valid"]).to be false }
  end
end
