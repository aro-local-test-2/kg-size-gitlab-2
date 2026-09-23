# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Issue Boards new issue', :js, feature_category: :planning_views do
  before do
    stub_licensed_features(board_milestone_lists: true)
  end

  let_it_be(:user)            { create(:user) }
  let_it_be(:group)           { create(:group, :public) }
  let_it_be(:project)         { create(:project, :public, group: group) }
  let_it_be(:milestone)       { create(:milestone, project: project, title: 'Milestone 1') }
  let_it_be(:board)           { create(:board, project: project) }
  let_it_be(:iteration) do
    create(:iteration, iterations_cadence: create(:iterations_cadence, title: "Test iteration", group: group))
  end

  let!(:milestone_list)       { create(:milestone_list, board: board, milestone: milestone, position: 0) }
  let!(:iteration_list)       { create(:iteration_list, board: board, iteration: iteration, position: 1) }

  context 'authorized user' do
    before do
      project.add_maintainer(user)

      sign_in(user)

      visit project_board_path(project, board)

      expect(page).to have_selector('.board', count: 4)
    end

    it 'successfully assigns weight to newly-created issue' do
      create_issue_in_board_list(0)

      within_testid('work-item-weight') do
        click_button 'Edit'
        find('input').set("10\n")
      end

      expect(page).to have_css('.board-card .board-card-weight .board-card-info-text', text: '10', exact_text: true)
    end

    describe 'milestone list' do
      it 'successfully loads milestone to be added to newly created issue' do
        create_issue_in_board_list(1)

        within_testid('work-item-milestone') do
          click_button 'Edit'

          expect(page).to have_content 'Milestone 1'
        end
      end
    end

    describe 'iteration list' do
      it 'successfully loads iteration to be added to newly created issue' do
        create_issue_in_board_list(2)

        within_testid('work-item-iteration') do
          expect(page).to have_content 'Test iteration'
        end
      end
    end

    describe 'board scoped to current iteration' do
      let!(:iteration) do
        create(:current_iteration, title: 'Iteration 1',
          iterations_cadence: create(:iterations_cadence, group: group),
          start_date: 3.days.ago, due_date: 3.days.from_now)
      end

      it 'adds a new issue' do
        scope_board_to_current_iteration

        expect { create_issue_in_board_list(0) }.to change { Issue.count }.by(1)

        within_testid('work-item-iteration') do
          expect(page).to have_content iteration.title
        end

        page.within('.board-card') do
          expect(page).to have_content 'new issue'
        end
      end
    end
  end

  def create_issue_in_board_list(list_index)
    page.within(all('.board', minimum: list_index + 1)[list_index]) do
      click_button 'Create new issue'
    end

    page.within(first('.board-new-issue-form')) do
      find('.form-control').set('new issue')
      click_button 'Create issue'
    end

    expect(page).to have_css('.board-card', text: 'new issue')
  end

  def scope_board_to_current_iteration
    find_by_testid('boards-config-button').click

    page.within(".iteration") do
      click_button 'Edit'

      page.within(".dropdown-menu") do
        expect(page).to have_testid('unselected-option')

        click_button "Current iteration"
      end

      expect(page).to have_testid('selected-iteration', text: 'Current iteration')
    end

    click_button 'Save changes'

    expect(page).to have_no_css('.board-config-modal')
  end
end
