package LJ::Widget::Location;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use DateTime::TimeZone;

my @location_props = qw/ country state city zip timezone sidx_loc/;


sub authas {1}
sub need_res { qw(js/countryregions.js) }

## The following options are supported by the render_body method
##      country         - initially selected country in country-dropbox; user prop is used for default value
##      city            - initial city value
##      state           - initial state value
##      skip_timezone   - timezone input is not displayed if true, defaults to 0
##      skip_zip        - zip input is not displayed if true, defaults to 0
##      skip_city       - city input is not displayed if true, defaults to 0
sub render_body {
    my $class = shift;
    my %opts = (
        # immediate values
        @_
    );

    # use "authas"-aware code
    my $u = $class->get_effective_remote;
    $u->preload_props(@location_props);

    # displayed country may be specified in %opts hash
    my $effective_country = exists $opts{'country'} ? $opts{'country'} : $u->prop('country');
    # displayed state and city may be specified in %opts hash
    my $effective_state = exists $opts{'state'} ? $opts{'state'} : $u->prop('state');
    my $effective_city = exists $opts{'city'} ? $opts{'city'} : $u->prop('city');

    # hashref of all available countries (country code => country name), it is passed to html_select method later
    my $country_options = $class->country_options;
    # check if specified country has regions
    my $regions_cfg = $class->country_regions_cfg($effective_country);
    # hashref of all regions for the specified country; it is initialized and used only if $regions_cfg is defined, i.e. the country has regions (states)
    my $state_options = $class->region_options($regions_cfg)
        if $regions_cfg;


    my $ret;

    $ret .= "<table class='field_block'>\n";

    $ret .= "<tr><td class='field_class'>" . $class->ml('widget.location.fn.country') . "</td><td>";
    $ret .= $class->html_select('id'        => 'country_choice',
                                'name'      => 'country',
                                'selected'  => $effective_country,
                                'class'     => 'country_choice_select',
                                'list'      => $country_options,
                                %{$opts{'country_input_attributes'} or {} },
                                );
    $ret .= "</td></tr>\n";

    $ret .= "<tr><td class='field_class'>" . $class->ml('widget.location.fn.state') . "</td><td>";

    # state
    $ret .= $class->html_select('id' => 'reloadable_states',
                                'name' => 'statedrop',
                                'selected' => ($regions_cfg ? $effective_state : ''),
                                'list' => $state_options,
                                'style' => 'display:' . ($regions_cfg ? 'block' : 'none'),
                                %{$opts{'state_inputselect_attributes'} or {} },
                                );
    # other state?
    $ret .= "<span style='white-space: nowrap'> ";
    $ret .= $class->html_text('id' => 'written_state',
                              'name' => 'stateother',
                              'value' => ($regions_cfg ? '' : $effective_state),
                              'size' => '20',
                              'style' => 'display:' . ($regions_cfg ? 'none' : 'block'),
                              'maxlength' => '50',
                               %{$opts{'state_inputtext_attributes'} or {} },
                              );
    $ret .= "</span>";

    $ret .= "</td></tr>\n";

    # zip
    unless ($opts{'skip_zip'}) {
        $ret .= "<tr><td class='field_class'>" . $class->ml('widget.location.fn.zip') . "</td><td>";
        $ret .= $class->html_text('id' => 'zip',
                                  'name' => 'zip',
                                  'value' => $effective_country eq 'US' ? $u->{'zip'} : '',
                                  'size' => '6', 'maxlength' => '5',
                                  'disabled' => $effective_country eq 'US' ? '' : 'disabled',
                                  );
        $ret .= " <span class='helper'>(" . $class->ml('widget.location.zip.usonly') . ")</span></td></tr>\n";
    }

    unless ($opts{'skip_city'}) {
        # city
        $ret .= "<tr><td class='field_class'>" . $class->ml('widget.location.fn.city') . "</td><td>";
        $ret .= $class->html_text('id' => 'city',
                                  'name' => 'city',
                                  'value' => $effective_city,
                                  'size' => '20',
                                  'maxlength' => '255',
                                   %{$opts{'state_input_attributes'} or {} },
                                  );
        $ret .= "</td></tr>\n";
    }

    unless ($opts{'skip_timezone'}) {
        # timezone
        $ret .= "<tr><td class='field_class'>" . $class->ml('widget.location.fn.timezone') . "</td><td>";
        {
            my $map = DateTime::TimeZone::links();
            my $usmap = { map { $_ => $map->{$_} } grep { m!^US/! && $_ ne "US/Pacific-New" } keys %$map };
            my $camap = { map { $_ => $map->{$_} } grep { m!^Canada/! } keys %$map };

            $ret .= $class->html_select('name' => 'timezone',
                                        'selected' => $u->{'timezone'},
                                        'list' => [
                                            "", $class->ml('widget.location.timezone.select'),
                                            (map { $usmap->{$_}, $_ } sort keys %$usmap),
                                            (map { $camap->{$_}, $_ } sort keys %$camap),
                                            map { $_, $_ } DateTime::TimeZone::all_names()
                                        ]
                                        );
        }
        $ret .= "</td></tr>\n";
    }

    $ret .= "</table>\n";

    # javascript code in js/countryregions.js accepts list of countries with regions as a space-delimited list
    $ret .= "<script> var countryregions = new CountryRegions('country_choice', 'reloadable_states', 'written_state', 'zip', '" . join (" ", $class->countries_with_regions ). "'); </script>";

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;
    # use "authas"-aware code
    my $u = $class->get_effective_remote;
    # load country codes
    my %countries;
    LJ::load_codes({ "country" => \%countries});

    # state and zip
    my ($zipcity, $zipstate) = LJ::load_state_city_for_zip($post->{'zip'})
        if $post->{'country'} eq "US" && length $post->{'zip'} > 0;

    # country
    if ($post->{'country'} ne "US" && $post->{'zip'}) {
        $class->error($class->ml('widget.location.error.locale.zip_requires_us'));
    }

    my $regions_cfg = $class->country_regions_cfg($post->{'country'});
    if ($regions_cfg && $post->{'stateother'}) {
        $class->error($class->ml('widget.location.error.locale.country_ne_state'));
    } elsif (!$regions_cfg && $post->{'statedrop'}) {
        $class->error($class->ml('widget.location.error.locale.state_ne_country'));
    }

    # zip-code validation stuff
    if ($post->{'country'} eq "US") {
        if ($post->{'statedrop'} && $zipstate && $post->{'statedrop'} ne $zipstate) {
            $class->error($class->ml('widget.location.error.locale.zip_ne_state'));
        }
        if ($zipcity) {
            $post->{'statedrop'} = $zipstate;
            $post->{'city'} = $zipcity;
        }
    }

    if ($post->{'country'} && !defined($countries{$post->{'country'}})) {
        $class->error($class->ml('widget.location.error.locale.invalid_country'));
    }

    return if $class->error_list;

    $post->{'timezone'} = "" unless grep { $post->{'timezone'} eq $_ } DateTime::TimeZone::all_names();

    # check if specified country has states
    if ($regions_cfg) {
        # if it is - use region select dropbox
        $post->{'state'} = $post->{'statedrop'};
        # mind save_region_code also
        unless ($regions_cfg->{'save_region_code'}) {
            # save region name instead of code
            my $regions_arrayref = $class->region_options($regions_cfg);
            my %regions_as_hash = @$regions_arrayref;
            $post->{'state'} = $regions_as_hash{$post->{'state'}};
        }
    } else {
        # use state input box
        $post->{'state'} = $post->{'stateother'};
    }

    $post->{'sidx_loc'} = undef;
    if ($opts{'save_search_index'} && $post->{'country'}) {
        $post->{'sidx_loc'} = sprintf("%2s-%s-%s", $post->{'country'}, $post->{'state'}, $post->{'city'});
    }

    # set userprops
    $u->set_prop($_, $post->{$_}) foreach @location_props;

    return;
}

sub country_regions_cfg {
    my $class = shift;
    my $country = shift;
    return $LJ::COUNTRIES_WITH_REGIONS{$country};
}

sub countries_with_regions {
    keys %LJ::COUNTRIES_WITH_REGIONS;
}

sub country_options {
    my $class = shift;

    my %countries;
    # load country codes
    LJ::load_codes({ "country" => \%countries});

    my $options = ['' => $class->ml('widget.location.country.choose'), 'US' => 'United States',
                   map { $_, $countries{$_} } sort { $countries{$a} cmp $countries{$b} } keys %countries];
    return $options;
}

sub region_options {
    my $class = shift;
    my $country_region_cfg = shift;

    my %states = ();
    LJ::load_codes ({$country_region_cfg->{'type'} => \%states});

    my $options = ['' => $class->ml('states.head.defined'),
                   map { $_ , $states{$_} } sort keys %states];
    return $options;
}

1;
