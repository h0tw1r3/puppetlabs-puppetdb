# some provision environments (docker) may not setup or isolate domains
# this ensures the instance FQDN is always resolved locally
host { 'primary':
  name         => $facts['networking']['fqdn'],
  ip           => $facts['networking']['ip'],
  host_aliases => [
    $facts['networking']['hostname'],
  ],
}

# TODO: backport to litmusimage, required for serverspec tests
package { 'iproute': ensure => installed }

# TODO: rework this hack
if $facts['os']['family'] == 'RedHat' {
  if versioncmp($facts['os']['release']['major'], '8') >= 0 {
    package { 'disable-builtin-dnf-postgresql-module':
      ensure   => 'disabled',
      name     => 'postgresql',
      provider => 'dnfmodule',
    }

    Yumrepo <| tag == 'postgresql::repo' |>
    -> Package['disable-dnf-postgresql-module']
    -> Package <| tag == 'postgresql' |>
  } else {
    # ip6tables fails to start and causes a cascading failure on GH actions
    exec { '/usr/bin/env systemctl mask ip6tables.service': }
  }
}
