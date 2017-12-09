#!/usr/bin/perl

# Very simple single-file example of TUWF.

use strict;
use warnings;

# This is a trick I always use to get the absolute path of a file if we only
# know its location relative to the location of this script. It does not rely
# on getcwd() or environment variables, and thus works quite well.
#
# Of course, you won't need this when TUWF is properly installed (and thus
# available in @INC) and all other files you are using, too.

use Cwd 'abs_path';
our $ROOT;
BEGIN { ($ROOT = abs_path $0) =~ s{/examples/singlefile.pl$}{}; }
use lib $ROOT.'/lib';


# load TUWF and import all html functions
use TUWF ':html';

TUWF::set debug => 1;

# Register a handle for the root path, i.e. "GET /"
TUWF::get '/' => sub {
  # Generate an overly simple html page
  html;
   body;
    h1 'Hello World!';
    p 'Check out the following awesome links!';
    ul;
     for (qw|awesome cool etc|) {
       li; a href => "/sub/$_", $_; end;
     }
    end;
   end;
  end;
};


# Register a route handler for "GET /sub/*"
TUWF::get qr{/sub/(?<capturename>.*)} => sub {
  # output a plain text file containing $uri
  tuwf->resHeader('Content-Type' => 'text/plain; charset=UTF-8');
  lit tuwf->capture(1);
  lit "\n";
  lit tuwf->capture('capturename');
};


# Register a handler for "POST /api/echoapi.json"
TUWF::post '/api/echoapi.json' => sub {
  tuwf->resJSON(tuwf->reqJSON);
};


# "run" the framework. The script will now accept requests either through CGI,
# FastCGI, or run as a standalone server.
TUWF::run();
