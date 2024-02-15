require 'rspec/core'

desc "Check to ensure defined puppet code has been described in spec\n(defaults: coverage=100)"
task :spec_described, [:coverage] do |_task, args|
  args.with_defaults(coverage: '100')
  def pluralize(string)
    string.end_with?('s') ? "#{string}es" : "#{string}s"
  end

  def colorize(msg, color)
    @colorizer ||= ::RSpec::Core::Formatters::ConsoleCodes
    @colorizer.wrap(msg, color)
  end

  def coverage_color(pct, required = 100, warn: 0.5)
    if pct >= required.to_f
      :green
    elsif pct < required.to_f * warn.to_f
      :red
    else
      :yellow
    end
  end

  code = {}
  code_files = {}
  Dir.glob('{functions,manifests,types}/**/*.pp') do |fn|
    res_type = res_title = nil
    File.foreach(fn) do |line|
      if line =~ %r{^\s*(class|function|define|type|function)\s*([^=\{\s]+)}
        res_type = Regexp.last_match(1)
        res_type = 'type_alias' if res_type == 'type'
        res_title = Regexp.last_match(2)
        code[res_type] ||= []
        break
      end
    end
    if res_type
      code[res_type] << res_title if res_type
      code_files[res_title] = fn
    end
  end
  Dir.glob('lib/puppet/functions/**/*.rb') do |fn|
    File.foreach(fn) do |line|
      if line =~ %r{^\s*Puppet::Functions\.create_function\(:?['"]?([^']+)['"]?\)}
        code['function'] ||= []
        code['function'] << Regexp.last_match(1)
        code_files[Regexp.last_match(1)] = fn
      end
    end
  end

  test = {}
  test_files = {}
  Dir.glob('spec/{classes,defines,functions,type_aliases}/**/*rb') do |fn|
    resource_type = fn.split(File::SEPARATOR)[1].match(%r{(class|function|define|type_alias)}).captures[0]
    test[resource_type] ||= []
    File.foreach(fn) do |line|
      if (m = line.match(%r{^describe ["']([^'"\s]+)}))
        test[resource_type] << m.captures[0]
        test_files[m.captures[0]] = fn
      end
    end
  end

  def diff(a, b)
    a.merge(a) { |ka, va| va.reject { |v| b[ka]&.include?(v) } }
  end

  @missing = diff(code, test)
  @unknown = diff(test, code)

  total_want = code.values.flatten.size
  total_missing = @missing.values.flatten.size
  total_have = total_want - total_missing

  total_percent = total_have / total_want.to_f * 100
  total_color = coverage_color(total_percent, args[:coverage], warn: 1)

  puts "Spec described coverage: #{colorize('%3.1f%%' % total_percent, total_color)}"

  if total_have < total_want || !@unknown.values.flatten.empty?
    (code.keys | @missing.keys).each do |res_type|
      want = (code[res_type]&.size || 0)
      missing = (@missing[res_type]&.size || 0)
      coverage = (want - missing) / want.to_f * 100.0
      color = coverage_color(coverage, args[:coverage])
      puts "  * #{pluralize(res_type)}: #{colorize('%3.1f%%' % coverage, color)}"

      ['missing', 'unknown'].each do |how|
        what = instance_variable_get("@#{how}")
        next if what[res_type].nil? || what[res_type].empty?
        puts "    #{how}:"
        what[res_type].each do |r|
          info = " in #{test_files[r]}" if test_files[r]
          puts "    - #{r}#{info}"
        end
      end
    end
  end
  abort if total_percent < args[:coverage].to_f
end
