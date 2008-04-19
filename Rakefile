require 'rake'
require 'rake/testtask'
require 'rake/rdoctask'

desc 'Default: run unit tests.'
task :default => [:refresh_db, :test]

desc 'Remove old sqlite file'
task :refresh_db do
  `rm -f #{File.dirname(__FILE__)}/test/proxy_attributes.sqlite3`
end

desc 'Test the ProxyAttributes plugin.'
Rake::TestTask.new(:test) do |t|
  t.libs << 'lib'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = true
end

desc 'Generate documentation for the ProxyAttributes plugin.'
Rake::RDocTask.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = 'doc'
  rdoc.title    = 'ProxyAttributes'
  rdoc.options << '--line-numbers' << '--inline-source'
  rdoc.rdoc_files.include('README.rdoc')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

begin
  require 'rcov/rcovtask'
  desc 'Generate coverage tests for the ProxyAttributes plugin'
  Rcov::RcovTask.new do |t|
    t.libs << "test"
    t.test_files = FileList['test/**/*_test.rb']
    t.rcov_opts << '-x' << '"^\/"'
    if ENV['NON_NATIVE']
      t.rcov_opts << "--no-rcovrt"
    end
    t.verbose = true
  end
rescue LoadError
  # Carry on...
end
