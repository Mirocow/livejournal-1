package LJ::Widget::QotD;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::QotD );

sub need_res {
    return qw( js/widgets/qotd.js stc/widgets/qotd.css );
}

sub render_body {
    my $class = shift;
    my %opts = @_;
    my $ret;

    my $skip = $opts{skip};
    my $domain = $opts{domain};
    my $u = $opts{user} && LJ::isu($opts{user}) ? $opts{user} : LJ::get_remote();

    my $embed = $opts{embed};
    my $archive = $opts{archive};

    my @questions = $opts{question} || LJ::QotD->get_questions( user => $u, skip => $skip, domain => $domain );

    return "" unless @questions;

    unless ($embed || $archive) {
        my $title = LJ::run_hook("qotd_title", $u) || $class->ml('widget.qotd.title');
        $ret .= "<h2>$title";
    }

    unless ($opts{nocontrols}) {
        $ret .= "<span class='qotd-controls'>";
        $ret .= "<img id='prev_questions' src='$LJ::IMGPREFIX/arrow-spotlight-prev.gif' alt='Previous' title='Previous' /> ";
        $ret .= "<img id='prev_questions_disabled' src='$LJ::IMGPREFIX/arrow-spotlight-prev-disabled.gif' alt='Previous' title='Previous' /> ";
        $ret .= "<img id='next_questions' src='$LJ::IMGPREFIX/arrow-spotlight-next.gif' alt='Next' title='Next' />";
        $ret .= "<img id='next_questions_disabled' src='$LJ::IMGPREFIX/arrow-spotlight-next-disabled.gif' alt='Next' title='Next' />";
        $ret .= "</span>";
    }

    $ret .= "</h2>" unless $embed || $archive;

    $ret .= "<div id='all_questions'>" unless $opts{nocontrols};

    if ($embed) {
        $ret .= $class->qotd_display_embed( questions => \@questions, user => $u, %opts );
    } elsif ($archive) {
        $ret .= $class->qotd_display_archive( questions => \@questions, user => $u, %opts );
    } else {
        $ret .= $class->qotd_display( questions => \@questions, user => $u, %opts );
    }

    $ret .= "</div>" unless $opts{nocontrols};

    return $ret;
}

sub question_text {
    my $class = shift;
    my $qid = shift;

    my $ml_key = $class->ml_key("$qid.text");
    my $text = $class->ml($ml_key);
    LJ::CleanHTML::clean_event(\$text);

    return $text;
}

# version suitable for embedding in journal entries
sub qotd_display_embed {
    my $class = shift;
    my %opts = @_;

    my $questions = $opts{questions} || [];
    my $remote = LJ::get_remote();

    my $ret;
    if (@$questions) {
        # table used for better inline display
        $ret .= '<table cellpadding="0" cellspacing="0"><tr><td>';
        $ret .= "<div style='border: 1px solid #000; padding: 6px;'>";
        foreach my $q (@$questions) {

            # FIXME: this is a dirty hack because if this widget is put into a journal page
            #        as the first request of a given Apache, Apache::BML::cur_req will not
            #        be instantiated and we'll auto-vivify it with a call to BML::get_language()
            #        from within LJ::Lang.  We're working on a better fix.
            #
            #        -- Whitaker 2007/08/28

            #my $ml_key = $class->ml_key("$q->{qid}.text");
            #my $text = $class->ml($ml_key);
            my $text = $q->{text};
            LJ::CleanHTML::clean_event(\$text);

            my $from_text = '';
            if ($q->{from_user}) {
                my $from_u = LJ::load_user($q->{from_user});
                $from_text = "Submitted by " . $from_u->ljuser_display . "<br />"
                    if $from_u;
                #$from_text = $class->ml('widget.qotd.entry.submittedby', {'user' => $from_u->ljuser_display}) . "<br />"
                #    if $from_u;
            }

            my $qid = $q->{qid};
            my $answers_link = "<a href=\"$LJ::SITEROOT/misc/latestqotd.bml?qid=$qid\">" . $class->ml('widget.qotd.view.other.answers') . "</a>";

            my $answer_link = "";
            unless ($opts{no_answer_link}) {
                $answer_link = $class->answer_link
                    ($q, user => $opts{user}, button_disabled => $opts{form_disabled});
            }

            $ret .= "<p>$text</p><p style='font-size: 0.8em;'>$from_text</p><br />";
            $ret .= "<p>$answer_link $answers_link" . $class->impression_img($q) . "</p>";
        }
        $ret .= "</div></td></tr></table>";
    }

    return $ret;
}

# version suitable for the archive page
sub qotd_display_archive {
    my $class = shift;
    my %opts = @_;

    my $questions = $opts{questions} || [];
    my $remote = LJ::get_remote();

    my $ret;
    foreach my $q (@$questions) {
        my $ml_key = $class->ml_key("$q->{qid}.text");
        my $text = $class->ml($ml_key);
        LJ::CleanHTML::clean_event(\$text);

        my $qid = $q->{qid};
        my $answers_link = "<a href='$LJ::SITEROOT/misc/latestqotd.bml?qid=$qid'>" . $class->ml('widget.qotd.viewanswers') . "</a>";

        my $answer_link = "";
        unless ($opts{no_answer_link}) {
            $answer_link = $class->answer_link( $q, user => $opts{user}, button_disabled => $opts{form_disabled} );
        }

        my $date = DateTime->from_epoch( epoch => $q->{time_start}, time_zone => 'America/Los_Angeles' );

        $ret .= "<p class='qotd-archive-item-date'>" . $date->strftime("%B %e, %Y") . "</p>";
        $ret .= "<p class='qotd-archive-item-question'>$text</p>";
        $ret .= "<p class='qotd-archive-item-answers'>$answer_link $answers_link" . $class->impression_img($q) . "</p>";
    }

    return $ret;
}

sub qotd_display {
    my $class = shift;
    my %opts = @_;

    my $questions = $opts{questions} || [];
    my $remote = LJ::get_remote();

    my $ret;
    if (@$questions) {
        $ret .= "<div class='qotd'>";
        foreach my $q (@$questions) {
            my $ml_key = $class->ml_key("$q->{qid}.text");
            my $text = $class->ml($ml_key);
            LJ::CleanHTML::clean_event(\$text);

            my $extra_text;
            if ($q->{extra_text} && LJ::run_hook('show_qotd_extra_text', $remote)) {
                $ml_key = $class->ml_key("$q->{qid}.extra_text");
                $extra_text = $class->ml($ml_key);
                LJ::CleanHTML::clean_event(\$extra_text);
            }

            my $from_text;
            if ($q->{from_user}) {
                my $from_u = LJ::load_user($q->{from_user});
                $from_text = $class->ml('widget.qotd.entry.submittedby', {'user' => $from_u->ljuser_display}) . "<br />"
                    if $from_u;
            }

            $ret .= "<table><tr><td>";
            my $viewanswers;
            if ($opts{small_view_link}) {
                $viewanswers .= " <a class='small-view-link' href=\"$LJ::SITEROOT/misc/latestqotd.bml?qid=$q->{qid}\">" . $class->ml('widget.qotd.view.more') . "</a>";
            } else {
                $viewanswers .= " <br /><a href=\"$LJ::SITEROOT/misc/latestqotd.bml?qid=$q->{qid}\">" . $class->ml('widget.qotd.viewanswers') . "</a>";
            }

            $ret .= "$text " .
                $class->answer_link($q, user => $opts{user}, button_disabled => $opts{form_disabled}) .
                "$viewanswers";
            if ($q->{img_url}) {
                if ($q->{link_url}) {
                    $ret .= "</td><td><a href='$q->{link_url}'><img src='$q->{img_url}' class='qotd-img' alt='' /></a>";
                } else {
                    $ret .= "</td><td><img src='$q->{img_url}' class='qotd-img' alt='' />";
                }
            }
            $ret .= "</td></tr></table>";

            my $archive = "<a href='$LJ::SITEROOT/misc/qotdarchive.bml'>" . $class->ml('widget.qotd.archivelink') . "</a>";
            my $suggest = "<a href='$LJ::SITEROOT/misc/suggest_qotd.bml'>" . $class->ml('widget.qotd.suggestions') . "</a>";
            $ret .= "<p class='detail'><span class='suggestions'>$archive | $suggest</span>$from_text$extra_text" . $class->impression_img($q) . "&nbsp;</p>";
        }
        $ret .= "</div>";
    }

    return $ret;
}

sub answer_link {
    my $class = shift;
    my $question = shift;
    my %opts = @_;

    my $url = $class->answer_url($question, user => $opts{user});
    my $txt = LJ::run_hook("qotd_answer_txt", $opts{user}) || $class->ml('widget.qotd.answer');
    my $dis = $opts{button_disabled} ? "disabled='disabled'" : "";
    my $onclick = qq{onclick="document.location.href='$url'"};

    # if button is disabled, don't attach an onclick
    my $extra = $dis ? $dis : $onclick;

    return qq{<input type="button" value="$txt" $extra />};
}

sub answer_url {
    my $class = shift;
    my $question = shift;
    my %opts = @_;

    return "$LJ::SITEROOT/update.bml?qotd=$question->{qid}";
}

sub subject_text {
    my $class = shift;
    my $question = shift;
    my %opts = @_;

    my $ml_key = $class->ml_key("$question->{qid}.subject");
    my $subject = LJ::run_hook("qotd_subject", $opts{user}, $class->ml($ml_key)) ||
        $class->ml('widget.qotd.entry.subject', {'subject' => $class->ml($ml_key)});

    return $subject;
}

sub embed_text {
    my $class = shift;
    my $question = shift;

    return qq{<lj-template name="qotd" id="$question->{qid}" />};
}    

sub event_text {
    my $class = shift;
    my $question = shift;
    my %opts = @_;

    my $remote = LJ::get_remote();
    my $ml_key = $class->ml_key("$question->{qid}.text");

    my $event = $class->ml($ml_key);
    my $from_user = $question->{from_user};
    my $extra_text = LJ::run_hook('show_qotd_extra_text', $remote) ? $question->{extra_text} : "";

    if ($from_user || $extra_text) {
        $event .= "\n<span style='font-size: smaller;'>";
        $event .= $class->ml('widget.qotd.entry.submittedby', {'user' => "<lj user='$from_user'>"}) if $from_user;
        $event .= "\n" if $from_user && $extra_text;
        $event .= $extra_text if $extra_text;
        $event .= "</span>";
    }

    return $event;
}

sub tags_text {
    my $class = shift;
    my $question = shift;
    my %opts = @_;

    my $tags = $question->{tags};

    return $tags;
}

sub impression_img {
    my $class = shift;
    my $question = shift;

    my $impression_url;
    if ($question->{impression_url}) {
        $impression_url = LJ::PromoText->parse_url( qid => $question->{qid}, url => $question->{impression_url} );
    }

    return $impression_url && LJ::run_hook("should_see_special_content", LJ::get_remote()) ? "<img src=\"$impression_url\" border='0' width='1' height='1' alt='' />" : "";
}

sub questions_exist_for_user {
    my $class = shift;
    my %opts = @_;

    my $skip = $opts{skip};
    my $domain = $opts{domain};
    my $u = $opts{user} && LJ::isu($opts{user}) ? $opts{user} : LJ::get_remote();

    my @questions = LJ::QotD->get_questions( user => $u, skip => $skip, domain => $domain );

    return scalar @questions ? 1 : 0;
}

1;
