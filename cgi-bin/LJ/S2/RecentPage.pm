use strict;
package LJ::S2;

sub RecentPage
{
    my ($u, $remote, $opts) = @_;

    my $p = Page($u, $opts);
    $p->{'_type'} = "RecentPage";
    $p->{'view'} = "recent";
    $p->{'entries'} = [];

    my $dbr = LJ::get_db_reader();
    my $dbcr = LJ::get_cluster_reader($u);

    my $user = $u->{'user'};
    my $journalbase = LJ::journal_base($user, $opts->{'vhost'});

    if ($u->{'journaltype'} eq "R" && $u->{'renamedto'} ne "") {
        $opts->{'redir'} = LJ::journal_base($u->{'renamedto'}, $opts->{'vhost'});
        return;
    }

    LJ::load_user_props($dbr, $remote, "opt_nctalklinks");

    my $get = $opts->{'getargs'};

    if ($opts->{'pathextra'}) {
        $opts->{'badargs'} = 1;
        return 1;
    }
    
    if ($u->{'opt_blockrobots'} || $get->{'skip'}) {
        $p->{'head_content'} .= LJ::robot_meta_tags();
    }

    my $itemshow = S2::get_property_value($opts->{'ctx'}, "page_recent_items")+0;
    if ($itemshow < 1) { $itemshow = 20; }
    elsif ($itemshow > 50) { $itemshow = 50; }
    
    my $skip = $get->{'skip'}+0;
    my $maxskip = $LJ::MAX_HINTS_LASTN-$itemshow;
    if ($skip < 0) { $skip = 0; }
    if ($skip > $maxskip) { $skip = $maxskip; }

    # do they want to view all entries, regardless of security?
    my $viewall = 0;
    if ($get->{'viewall'} && LJ::check_priv($dbr, $remote, "viewall")) {
        LJ::statushistory_add($u->{'userid'}, $remote->{'userid'}, 
                              "viewall", "lastn: $user");
        $viewall = 1;
    }

    ## load the itemids
    my @itemids;
    my $err;
    my @items = LJ::get_recent_items({
        'clusterid' => $u->{'clusterid'},
        'clustersource' => 'slave',
        'viewall' => $viewall,
        'userid' => $u->{'userid'},
        'remote' => $remote,
        'itemshow' => $itemshow,
        'skip' => $skip,
        'itemids' => \@itemids,
        'dateformat' => 'S2',
        'order' => ($u->{'journaltype'} eq "C" || $u->{'journaltype'} eq "Y")  # community or syndicated
            ? "logtime" : "",
        'err' => \$err,
    });

    die $err if $err;
    
    ### load the log properties
    my %logprops = ();
    my $logtext;
    LJ::load_log_props2($dbcr, $u->{'userid'}, \@itemids, \%logprops);
    $logtext = LJ::get_logtext2($u, @itemids);
    LJ::load_moods();

    my $lastdate = "";
    my $itemnum = 0;
    my $lastentry = undef;

    my (%apu, %apu_lite);  # alt poster users; UserLite objects
    foreach (@items) {
        next unless $_->{'posterid'} != $u->{'userid'};
        $apu{$_->{'posterid'}} = undef;
    }
    if (%apu) {
        LJ::load_userids_multiple($dbr, [map { $_, \$apu{$_} } keys %apu], [$u]);
        $apu_lite{$_} = UserLite($apu{$_}) foreach keys %apu;
    }

    my $userlite_journal = UserLite($u);

  ENTRY:
    foreach my $item (@items) 
    {
        my ($posterid, $itemid, $security, $alldatepart, $replycount) = 
            map { $item->{$_} } qw(posterid itemid security alldatepart replycount);

        my $subject = $logtext->{$itemid}->[0];
        my $text = $logtext->{$itemid}->[1];

        # don't show posts from suspended users
        next ENTRY if $apu{$posterid} && $apu{$posterid}->{'statusvis'} eq 'S';

	if ($LJ::UNICODE && $logprops{$itemid}->{'unknown8bit'}) {
	    LJ::item_toutf8($u, \$subject, \$text, $logprops{$itemid});
	}

        my $date = substr($alldatepart, 0, 10);
        my $new_day = 0;
        if ($date ne $lastdate) {
            $new_day = 1;
            $lastdate = $date;
            $lastentry->{'end_day'} = 1 if $lastentry;
        }

        $itemnum++;
        LJ::CleanHTML::clean_subject(\$subject) if $subject;

        my $ditemid = $itemid * 256 + $item->{'anum'};
        LJ::CleanHTML::clean_event(\$text, { 'preformatted' => $logprops{$itemid}->{'opt_preformatted'},
                                              'cuturl' => LJ::item_link($u, $itemid, $item->{'anum'}), });
        LJ::expand_embedded($dbr, $ditemid, $remote, \$text);

        my $nc = "";
        $nc .= "nc=$replycount" if $replycount && $remote && $remote->{'opt_nctalklinks'};

        my $permalink = "$journalbase/$ditemid.html";
        my $readurl = $permalink;
        $readurl .= "?$nc" if $nc;
        my $posturl = $permalink . "?mode=reply";

        my $comments = CommentInfo({
            'read_url' => $readurl,
            'post_url' => $posturl,
            'count' => $replycount,
            'enabled' => ($u->{'opt_showtalklinks'} eq "Y" && ! $logprops{$itemid}->{'opt_nocomments'}) ? 1 : 0,
            'screened' => ($logprops{$itemid}->{'hasscreened'} && ($remote->{'user'} eq $u->{'user'}|| LJ::check_rel($dbr, $u, $remote, 'A'))) ? 1 : 0,
        });
        
        my $userlite_poster = $userlite_journal;
        my $userpic = $p->{'journal'}->{'default_pic'};
        my $pu = $u;
        if ($u->{'userid'} != $posterid) {
            $userlite_poster = $apu_lite{$posterid} or die "No apu_lite for posterid=$posterid";
            $pu = $apu{$posterid};
        }
        $userpic = Image_userpic($pu, 0, $logprops{$itemid}->{'picture_keyword'})
            if $logprops{$itemid}->{'picture_keyword'};

        my $entry = $lastentry = Entry($u, {
            'subject' => $subject,
            'text' => $text,
            'dateparts' => $alldatepart,
            'security' => $security,
            'props' => $logprops{$itemid},
            'itemid' => $ditemid,
            'journal' => $userlite_journal,
            'poster' => $userlite_poster,
            'comments' => $comments,
            'new_day' => $new_day,
            'end_day' => 0,   # if true, set later
            'userpic' => $userpic,
            'permalink_url' => $permalink,
        });

        push @{$p->{'entries'}}, $entry;

    } # end huge while loop

    # mark last entry as closing.
    $p->{'entries'}->[-1]->{'end_day'} = 1 if $itemnum;

    #### make the skip links
    my $nav = {
        '_type' => 'RecentNav',
        'version' => 1,
        'skip' => $skip,
    };

    # if we've skipped down, then we can skip back up
    if ($skip) {
        my $newskip = $skip - $itemshow;
        $newskip = 0 if $newskip <= 0;
        $nav->{'forward_skip'} = $newskip;
        $nav->{'forward_url'} = $newskip ? "$p->{'base_url'}/?skip=$newskip" : "$p->{'base_url'}/";
        $nav->{'forward_count'} = $itemshow;
    }

    # unless we didn't even load as many as we were expecting on this
    # page, then there are more (unless there are exactly the number shown 
    # on the page, but who cares about that)
    unless ($itemnum != $itemshow) {
        $nav->{'backward_count'} = $itemshow;
        if ($skip == $maxskip) {
            my $date_slashes = $lastdate;  # "yyyy mm dd";
            $date_slashes =~ s! !/!g;
            $nav->{'backward_url'} = "$p->{'base_url'}/day/$date_slashes";
        } else {
            my $newskip = $skip + $itemshow;
            $nav->{'backward_url'} = "$p->{'base_url'}/?skip=$newskip";
            $nav->{'backward_skip'} = $newskip;
        }
    }

    $p->{'nav'} = $nav;
    return $p;
}

1;
