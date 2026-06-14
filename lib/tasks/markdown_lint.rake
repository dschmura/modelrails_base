# frozen_string_literal: true

namespace :markdown do
  desc "Auto-fix markdown issues, then check for remaining violations"
  task :lint do
    sh "npx markdownlint --fix '**/*.md'"
    sh "npx markdownlint '**/*.md'"
  end

  desc "Check markdown for violations (CI — no auto-fix)"
  task :check do
    sh "npx markdownlint '**/*.md'"
  end
end
