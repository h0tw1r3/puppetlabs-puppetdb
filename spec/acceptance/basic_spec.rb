require 'spec_helper_acceptance'

describe 'basic tests' do
  let(:puppetdb_params) {}
  let(:puppetdb_master_config_params) {}
  # FIXME: temporary work-around for EL installs
  let(:postgres_version) { "($facts['os']['family'] == 'RedHat') ? { true => '12', default => undef }" }

  let(:pp) do
    <<~PP
    # FIXME: temporary work-around for EL installs
    if $facts['os']['family'] == 'RedHat' {
      $gpg_key_file = $facts['os']['release']['major'] ? {
        '7'     => 'PGDG-RPM-GPG-KEY-RHEL7',
        default => 'PGDG-RPM-GPG-KEY-RHEL',
      }
      file { "/etc/pki/rpm-gpg/${gpg_key_file}":
        source => "https://download.postgresql.org/pub/repos/yum/keys/${gpg_key_file}",
      }
      -> Yumrepo <| tag == 'postgresql::repo' |> {
        gpgkey => "file:///etc/pki/rpm-gpg/${gpg_key_file}",
      }
      # ip6tables service is broken on el7 under docker on GHA
      if Integer($facts['os']['release']['major']) < 8 {
        Service['ip6tables'] { enable => 'mask' }
      }
    }

    # reduce pgs memory
    postgresql::server::config_entry { 'max_connections': value => '20' }
    postgresql::server::config_entry { 'shared_buffers': value => '128kB' }
    postgresql::server::config_entry { 'effective_cache_size': value => '24MB' }
    postgresql::server::config_entry { 'maintenance_work_mem': value => '1MB' }
    postgresql::server::config_entry { 'checkpoint_completion_target': value => '0.9' }
    postgresql::server::config_entry { 'wal_buffers': value => '32kB' }
    postgresql::server::config_entry { 'random_page_cost': value => '4' }
    postgresql::server::config_entry { 'effective_io_concurrency': value => '2' }
    postgresql::server::config_entry { 'work_mem': value => '204kB' }
    postgresql::server::config_entry { 'huge_pages': value => 'off' }
    postgresql::server::config_entry { 'min_wal_size': value => '80MB' }
    postgresql::server::config_entry { 'max_wal_size': value => '1GB' }

    class { 'puppetdb':
      postgres_version            => #{postgres_version},
      database_max_pool_size      => '2',
      read_database_max_pool_size => '2',
      #{puppetdb_params}
    }
    -> class { 'puppetdb::master::config':
      #{puppetdb_master_config_params}
    }
    PP
  end

  describe 'puppetdb' do
    it 'applies idempotently' do
      idempotent_apply(pp, debug: ENV.key?('DEBUG'))
    end

    describe service('puppetdb'), :status do
      it { is_expected.to be_enabled }
      it { is_expected.to be_running }
    end

    describe port(8080), :status do
      it { is_expected.to be_listening }
    end

    describe port(8081), :status do
      it { is_expected.to be_listening }
    end

    context 'puppetdb postgres user', :status do
      it 'is not allowing read-only user to create tables' do
        run_shell('psql "postgresql://puppetdb-read:puppetdb-read@localhost/puppetdb" -c "create table tables(id int)"', expect_failures: true) do |r|
          expect(r.stderr).to match(%r{^ERROR:  permission denied for schema public.*})
          expect(r.exit_code).to eq 1
        end
      end

      it 'is allowing normal user to manage schema' do
        run_shell('psql "postgresql://puppetdb:puppetdb@localhost/puppetdb" -c "create table testing(id int); drop table testing"') do |r|
          expect(r.exit_status).to eq 0
        end
      end

      it 'is allowing read-only user to select' do
        run_shell('psql "postgresql://puppetdb-read:puppetdb-read@localhost/puppetdb" -c "select * from catalogs limit 1"') do |r|
          expect(r.exit_status).to eq 0
        end
      end
    end

    context 'manage report processor', :change do
      ['remove', 'add'].each do |outcome|
        context "#{outcome}s puppet config puppetdb report processor" do
          let(:enable_reports) { (outcome == 'add') ? true : false }

          let(:puppetdb_master_config_params) do
            <<~EOS
              manage_report_processor => true,
              enable_reports          => #{enable_reports},
            EOS
          end

          it 'applies manifest' do
            apply_manifest(pp, expect_failures: false, debug: ENV.key?('DEBUG'))
          end

          describe command('puppet config print --section master reports') do
            its(:stdout) do
              option = enable_reports ? 'to' : 'not_to'
              is_expected.method(option).call match 'puppetdb'
            end
          end
        end
      end
    end
  end

  describe 'puppetdb with postgresql ssl', :change do
    let(:puppetdb_params) do
      <<~EOS
        postgresql_ssl_on       => true,
        database_listen_address => '0.0.0.0',
        database_host           => $facts['networking']['fqdn'],
      EOS
    end

    it 'applies idempotently' do
      idempotent_apply(pp, debug: ENV.key?('DEBUG'))
    end
  end

  describe 'set wrong database password in puppetdb conf', :change do
    it 'applies manifest' do
      pp = <<~EOS
        ini_setting { "puppetdb password":
          ensure  => present,
          path    => '/etc/puppetlabs/puppetdb/conf.d/database.ini',
          section => 'database',
          setting => 'password',
          value   => 'random_password',
        }
        ~> service { 'puppetdb':
          ensure => 'running',
        }
        EOS

      apply_manifest(pp, expect_failures: false, debug: ENV.key?('DEBUG'))
    end

    describe service('puppetdb') do
      it { is_expected.to be_running }
    end
  end
end
