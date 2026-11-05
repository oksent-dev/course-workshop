CI.run do
  step "Setup", "ruby bin/setup"
  step "Style", "ruby bin/rubocop"
  step "Security: Rails", "ruby bin/brakeman --no-pager"
  step "Security: gems", "ruby bin/bundler-audit"
  step "Security: JavaScript", "npm audit"
  step "Autoloading", "ruby bin/rails zeitwerk:check"
  step "Tests", "ruby bin/rails test"
  step "System tests", "ruby bin/rails test:system"
end
