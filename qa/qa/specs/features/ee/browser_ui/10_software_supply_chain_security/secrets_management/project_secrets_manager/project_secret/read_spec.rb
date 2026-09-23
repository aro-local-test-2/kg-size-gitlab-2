# frozen_string_literal: true

module QA
  RSpec.describe(
    'Software Supply Chain Security',
    :secrets_manager,
    :orchestrated,
    :requires_admin,
    feature_category: :secrets_management
  ) do
    include_context 'secrets manager base'
    describe 'Project Secret' do
      def reporter
        @reporter ||= create(:user)
      end

      before(:context) do
        project.add_member(reporter, Resource::Members::AccessLevel::REPORTER)
      end

      context 'when reading a project secret' do
        it 'returns 404 when Reporter has no read permissions' do
          Flow::Login.while_signed_in(as: reporter) do
            visit("#{project.web_url}/-/secrets")

            expect(page).to have_text('404: Page not found')
          end
        end
      end
    end
  end
end
