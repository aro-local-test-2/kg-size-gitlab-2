# frozen_string_literal: true

require 'spec_helper'

RSpec.shared_examples 'an error occurred' do
  it 'communicates failure', :aggregate_failures do
    expect(subject).to be_error
    expect(subject.errors).to include(error_message)
  end
end
