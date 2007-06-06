package LJ::Event;
use strict;
no warnings 'uninitialized';

use Carp qw(croak);
use LJ::ModuleLoader;
use Class::Autouse qw(
                      LJ::ESN
                      LJ::Subscription
                      LJ::Typemap
                      );

my @EVENTS = LJ::ModuleLoader->module_subclasses("LJ::Event");
foreach my $event (@EVENTS) {
    eval "use $event";
    die "Error loading event module '$event': $@" if $@;
}

# Guide to subclasses:
#    LJ::Event::JournalNewEntry    -- a journal (user/community) has a new entry in it
#                                   ($ju,$ditemid,undef)
#    LJ::Event::UserNewEntry       -- a user posted a new entry in some journal
#                                   ($u,$journalid,$ditemid)
#    LJ::Event::JournalNewComment  -- a journal has a new comment in it
#                                   ($ju,$jtalkid)   # TODO: should probably be ($ju,$jitemid,$jtalkid)
#    LJ::Event::UserNewComment     -- a user left a new comment somewhere
#                                   ($u,$journalid,$jtalkid)
#    LJ::Event::Befriended         -- user $fromuserid added $u as a friend
#                                   ($u,$fromuserid)
#    LJ::Event::CommunityInvite    -- user $fromuserid invited $u to join $commid community)
#                                   ($u,$fromuserid, $commid)
#    LJ::Event::InvitedFriendJoins -- user $u1 was invited to join by $u2 and created a journal
#                                   ($u1, $u2)
#    LJ::Event::NewUserpic         -- user $u uploaded userpic $up
#                                   ($u,$up)
#    LJ::Event::UserExpunged       -- user $u is expunged
#                                   ($u)
#    LJ::Event::Birthday           -- user $u's birthday
#                                   ($u)
#    LJ::Event::PollVote           -- $u1 voted in poll $p posted by $u
#                                   ($u, $u1, $up)
sub new {
    my ($class, $u, @args) = @_;
    croak("too many args")        if @args > 2;
    croak("args must be numeric") if grep { /\D/ } @args;
    croak("u isn't a user")       unless LJ::isu($u);

    return bless {
        u => $u,
        args => \@args,
    }, $class;
}

# Class method
sub new_from_raw_params {
    my (undef, $etypeid, $journalid, $arg1, $arg2) = @_;

    my $class   = LJ::Event->class($etypeid) or die "Classname cannot be undefined/false";
    my $journal = LJ::load_userid($journalid) or die "Invalid journalid $journalid";
    my $evt     = LJ::Event->new($journal, $arg1, $arg2);

    # bless into correct class
    bless $evt, $class;

    return $evt;
}

sub raw_params {
    my $self = shift;
    use Data::Dumper;
    my $ju = $self->event_journal or
        Carp::confess("Event $self has no journal: " . Dumper($self));
    my @params = map { $_+0 } ($self->etypeid,
                               $ju->{userid},
                               $self->{args}[0],
                               $self->{args}[1]);
    return wantarray ? @params : \@params;
}

# Override this.  by default, events are rare, so subscriptions to
# them are tracked in target's "has_subscription" table.
# for common events, change this to '1' in subclasses and events
# will always fire without consulting the "has_subscription" table
sub is_common {
    0;
}

# Override this with a false value if subscriptions to this event should
# not show up in normal UI
sub is_visible { 1 }

# Override this with HTML containing the actual event
sub content { '' }

sub as_string {
    my ($self, $u) = @_;

    croak "No target passed to Event->as_string" unless LJ::isu($u);

    my ($classname) = (ref $self) =~ /Event::(.+?)$/;
    return "Event $classname fired for user=$u->{user}, args=[@{$self->{args}}]";
}

# default is just return the string, override if subclass
# actually can generate pretty content
sub as_html {
    my ($self, $u) = @_;

    croak "No target passed to Event->as_string" unless LJ::isu($u);

    return $self->as_string;
}

# what gets sent over IM, can be overridden
sub as_im {
    my ($self, $u) = @_;
    return $self->as_string($u);
}

# plaintext email subject
sub as_email_subject {
    my ($self, $u) = @_;
    return $self->as_string($u);
}

# contents for HTML email
sub as_email_html {
    my ($self, $u) = @_;
    return $self->as_email_string($u);
}

# contents for plaintext email
sub as_email_string {
    my ($self, $u) = @_;
    return $self->as_string($u);
}

# the "From" line for email
sub as_email_from_name {
    my ($self, $u) = @_;
    return $LJ::SITENAMESHORT;
}

# Optional headers (for comment notifications)
sub as_email_headers {
    my ($self, $u) = @_;
    return undef;
}

# class method, takes a subscription
sub subscription_as_html {
    my ($class, $subscr) = @_;

    croak "No subscription" unless $subscr;

    my $arg1 = $subscr->arg1;
    my $arg2 = $subscr->arg2;
    my $journalid = $subscr->journalid;

    my $user = $journalid ? LJ::ljuser(LJ::load_userid($journalid)) : "(wildcard)";

    return $class . " arg1: $arg1 arg2: $arg2 user: $user";
}

sub as_sms {
    my $self = shift;
    my $str = $self->as_string;
    return $str if length $str <= 160;
    return substr($str, 0, 157) . "...";
}

# override in subclasses
sub subscription_applicable {
    my ($class, $subscr) = @_;

    return 1;
}

# can $u subscribe to this event?
sub available_for_user  {
    my ($class, $u, $subscr) = @_;

    return 1;
}

############################################################################
#            Don't override
############################################################################

sub event_journal { &u; }
sub u    {  $_[0]->{u} }
sub arg1 {  $_[0]->{args}[0] }
sub arg2 {  $_[0]->{args}[1] }


# class method
sub process_fired_events {
    my $class = shift;
    croak("Can't call in web context") if LJ::is_web_context();
    LJ::ESN->process_fired_events;
}

# instance method.
# fire either logs the event to the delayed work system to be
# processed later, or does nothing, if it's a rare event and there
# are no subscriptions for the event.
sub fire {
    my $self = shift;
    my $u = $self->{u};
    return 0 if $LJ::DISABLED{'esn'};

    my $sclient = LJ::theschwartz();
    return 0 unless $sclient;

    my $job = $self->fire_job or
        return 0;

    my $h = $sclient->insert($job);
    return $h ? 1 : 0;
}

# returns the job object that would've fired, so callers can batch them together
# in one insert_jobs (plural) call.  returns empty list or single item.  doesn't
# return undef.
sub fire_job {
    my $self = shift;
    my $u = $self->{u};
    return if $LJ::DISABLED{'esn'};

    if (my $val = $LJ::DEBUG{'firings'}) {
        if (ref $val eq "CODE") {
            $val->($self);
        } else {
            warn $self->as_string . "\n";
        }
    }

    return unless $self->should_enqueue;

    return TheSchwartz::Job->new_from_array("LJ::Worker::FiredEvent", [ $self->raw_params ]);
}

sub subscriptions {
    my ($self, %args) = @_;
    my $cid   = delete $args{'cluster'};  # optional
    my $limit = delete $args{'limit'};    # optional
    croak("Unknown options: " . join(', ', keys %args)) if %args;
    croak("Can't call in web context") if LJ::is_web_context();

    # allsubs
    my @subs;

    my $allmatch = 0;
    my $zeromeans = $self->zero_journalid_subs_means;

    my @wildcards_from;
    if ($zeromeans eq 'friends') {
        # find friendofs, add to @wildcards_from
        @wildcards_from = LJ::get_friendofs($self->u);
    } elsif ($zeromeans eq 'all') {
        $allmatch = 1;
    }

    my $limit_remain = $limit;

    # SQL to match only on active and enabled subs
    my $and_enabled = "AND flags & " .
        (LJ::Subscription->INACTIVE | LJ::Subscription->DISABLED) . " = 0";

    # TODO: gearman parallelize:
    foreach my $cid ($cid ? ($cid) : @LJ::CLUSTERS) {
        # we got enough subs
        last if $limit && $limit_remain <= 0;

        my $udbh = LJ::get_cluster_master($cid)
            or die;

        # first we find exact matches (or all matches)
        my $journal_match = $allmatch ? "" : "AND journalid=?";
        my $limit_sql = $limit_remain ? "LIMIT $limit_remain" : '';
        my $sql = "SELECT userid, subid, is_dirty, journalid, etypeid, " .
            "arg1, arg2, ntypeid, createtime, expiretime, flags  " .
            "FROM subs WHERE etypeid=? $journal_match $and_enabled $limit_sql";

        my $sth = $udbh->prepare($sql);
        my @args = ($self->etypeid);
        push @args, $self->{u}->{userid} unless $allmatch;
        $sth->execute(@args);
        if ($sth->err) {
            warn "SQL: [$sql], args=[@args]\n";
            die $sth->errstr;
        }

        while (my $row = $sth->fetchrow_hashref) {
            push @subs, LJ::Subscription->new_from_row($row);
        }

        # then we find wildcard matches.
        if (@wildcards_from) {
            # FIXME: journals are only on one cluster! split jidlist based on cluster
            my $jidlist = join(",", @wildcards_from);

            my $sth = $udbh->prepare(
                                     "SELECT userid, subid, is_dirty, journalid, etypeid, " .
                                     "arg1, arg2, ntypeid, createtime, expiretime, flags  " .
                                     "FROM subs WHERE etypeid=? AND journalid=0 $and_enabled AND userid IN ($jidlist)"
                                     );

            $sth->execute($self->etypeid);
            die $sth->errstr if $sth->err;

            while (my $row = $sth->fetchrow_hashref) {
                push @subs, LJ::Subscription->new_from_row($row);
            }
        }

        $limit_remain = $limit - @subs;
    }

    return @subs;
}

# valid values are nothing ("" or undef), "all", or "friends"
sub zero_journalid_subs_means { "friends" }

# INSTANCE METHOD: SHOULD OVERRIDE if the subscriptions support filtering
sub matches_filter {
    my ($self, $subsc) = @_;
    return 1;
}

# instance method. Override if possible.
# returns when the event happened, or undef if unknown
sub eventtime_unix {
    return undef;
}

# instance method
sub should_enqueue {
    my $self = shift;
    return 1;  # for now.
    return $self->is_common || $self->has_subscriptions;
}

# instance method
sub has_subscriptions {
    my $self = shift;
    return 1; # FIXME: consult "has_subs" table
}


# get the typemap for the subscriptions classes (class/instance method)
sub typemap {
    return LJ::Typemap->new(
        table       => 'eventtypelist',
        classfield  => 'class',
        idfield     => 'etypeid',
    );
}

# returns the class name, given an etypid
sub class {
    my ($class, $typeid) = @_;
    my $tm = $class->typemap
        or return undef;

    $typeid ||= $class->etypeid;

    return $tm->typeid_to_class($typeid);
}

# returns the eventtypeid for this site.
# don't override this in subclasses.
sub etypeid {
    my ($class_self) = @_;
    my $class = ref $class_self ? ref $class_self : $class_self;

    my $tm = $class->typemap
        or return undef;

    return $tm->class_to_typeid($class);
}

# Class method
sub event_to_etypeid {
    my ($class, $evt_name) = @_;
    $evt_name = "LJ::Event::$evt_name" unless $evt_name =~ /^LJ::Event::/;
    my $tm = $class->typemap
        or return undef;
    return $tm->class_to_typeid($evt_name);
}

# this returns a list of all possible event classes
# class method
sub all_classes {
    my $class = shift;

    # return config'd classes if they exist, otherwise just return everything that has a mapping
    return @LJ::EVENT_TYPES if @LJ::EVENT_TYPES;

    croak "all_classes is a class method" unless $class;

    my $tm = $class->typemap
        or croak "Bad class $class";

    return $tm->all_classes;
}

1;
