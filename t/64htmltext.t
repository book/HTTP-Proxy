use strict;
use vars qw( @tokens );

BEGIN {
    @tokens = (
        "\n",                               "\n",
        "\nVous Etes Perdu ?\n",            "\n",
        "\n",                               "\n",
        "Perdu sur l'Internet ?",           "\n",
        "Pas de panique, on va vous aider", "\n",
        "    * ",                           "<-",
        "---- vous ",                       "tes ici",
        "\n",                               "\n",
        "\n\n"
    );
}

use Test::More tests => scalar @tokens;
use HTTP::Proxy::BodyFilter::htmltext;

# the tests are in the HTTP::Proxy::BodyFilter::htmltext callback
my $sub = sub { is( $_, shift (@tokens), "Correct text token matched" ); };
my $data =
qq{<HTML>\n<HEAD>\n<TITLE>\nVous Etes Perdu ?\n</TITLE>\n</HEAD>\n<BODY>\n<H1>Perdu sur l'Internet ?</H1>\n<H2>Pas de panique, on va vous aider</H2>\n<STRONG><PRE>    * <----- vous &ecirc;tes ici</PRE></STRONG>\n</BODY>\n</HTML>\n\n};

# test the filter's parser
my $filter = HTTP::Proxy::BodyFilter::htmltext->new($sub);
$filter->filter( \$data, undef, undef, undef );

# test the result data
