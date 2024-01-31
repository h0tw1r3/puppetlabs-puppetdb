# frozen_string_literal: true

require 'singleton'
class LitmusHelper
  include Singleton
  include PuppetLitmus
end

Dir['./spec/support/acceptance/**/*.rb'].sort.each { |f| require f }

RSpec.configure do |c|
  c.before :suite do
    manifest = File.read(File.join(File.dirname(__FILE__), 'fixtures/before_suite.pp'))
    LitmusHelper.instance.apply_manifest(manifest, expect_failures: false)
  end
end

RSpec::Matchers.define(:be_one_of) do |expected|
  match do |actual|
    expected.include?(actual)
  end

  failure_message do |actual|
    "expected one of #{expected}, got #{actual}"
  end
end