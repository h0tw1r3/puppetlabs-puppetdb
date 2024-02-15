# frozen_string_literal: true

require 'spec_helper'

# FIXME: the connection validator resource in this code was deprecated and
#        removed from the postgres module long ago.
#        although the class is included, the resource is never added to
#        the catalog, masking the unknown resource error, because
#        jdbc_ssl_properties returns '' instead of false.
describe 'puppetdb::server::validate_read_db', type: :class do
  let(:facts) { on_supported_os.take(1).first[1] }

  context 'with default params' do
    it {
      is_expected.to contain_class('puppetdb::server::validate_read_db')
        .with(
          database_host:     'localhost',
          database_port:     '5432',
          database_username: 'puppetdb',
          database_password: 'puppetdb',
          database_name:     'puppetdb',
          jdbc_ssl_properties: '',
        )
    }

    it { is_expected.not_to contain_postgresql__validate_db_connection('validate puppetdb postgres (read) connection') }
  end

  context 'with parameter tests' do
    let(:params) { { jdbc_ssl_properties: false } }

    context 'with jdbc_ssl_properties set false' do
      it {
        is_expected.to contain_postgresql__validate_db_connection('validate puppetdb postgres (read) connection')
          .with(
            database_host:     'localhost',
            database_port:     '5432',
            database_username: 'puppetdb',
            database_password: 'puppetdb',
            database_name:     'puppetdb',
          )
      }
    end

    context 'without database password' do
      let(:params) { { database_password: nil } }

      it { is_expected.not_to contain_postgresql__validate_db_connection('validate puppetdb postgres (read) connection') }
    end
  end
end
