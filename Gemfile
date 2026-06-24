# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# ruby-oci8 is a native extension that links against Oracle Instant Client (a
# separately installed, proprietary prerequisite). It lives in an optional group
# so the default bundle stays pure Ruby and installable anywhere - including CI,
# where the test suite runs against a fake OCI8 and never touches a database.
#
# To make real Oracle connections, install Instant Client, then:
#   bundle config set --local with oracle
#   bundle install
group :oracle, optional: true do
  gem "ruby-oci8", "~> 2.2"
end
