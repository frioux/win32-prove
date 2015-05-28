package
   API;

use Moo;

use experimental 'postderef';

use AWS::Signature4;
use Capture::Tiny 'capture';
use Future;
use Future::Utils 'repeat';
use HTTP::Request;
use HTTP::Request::Common 'POST';
use JSON;
use Net::Async::HTTP;
use Try::Tiny;
use URI;
use XML::Simple 'XMLin';

has _signer => (
   is => 'ro',
   lazy => 1,
   builder => sub {
       AWS::Signature4->new(
          -access_key => 'AKIAIX4VB7VY7DHWNYCA',
          -secret_key => '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',
       );
   },
   handles => {
      _sign => 'sign',
   },
);

has _loop => (
   is => 'ro',
   init_arg => 'loop',
   required => 1,
   handles => {
      _add_to_loop => 'add',
      _remove_from_loop => 'remove',
      _delay => 'delay_future',
   },
);

has _ua => (
   is => 'ro',
   lazy => 1,
   handles => {
      _do_request => 'do_request',
   },
   builder => sub {
      my $self = shift;

      my $ua = Net::Async::HTTP->new(
         fail_on_error => 1,
      );

      $self->_add_to_loop($ua);

      $ua
   },
);

sub _aws_request {
   my ($self, $request) = @_;

   $self->_sign($request);
   $self->_do_request(
      request => $request,
   )
}

sub create_key_pair {
   my $name = shift;
   decode_json(capture {
      system qw( aws ec2 create-key-pair --key-name), $name
   });
}

sub _describe_instances {
   my ($self, $args) = @_;

   $self->_aws_request(
      POST 'https://ec2.us-west-2.amazonaws.com/',
      content_type => 'application/x-www-form-urlencoded',
      Content => [
         Action => 'DescribeInstances',
         Version => '2015-04-15',
         %$args,
      ],
   )
}

sub describe_instances {
   shift->_describe_instances(@_)->then(sub {
      Future->done(XMLin($_[0]->decoded_content))
   }, sub {
      my ($code, $type, $res, $req) = @_;
      my $data = XMLin($res->decoded_content);

      Future->fail(
         $data->{Errors}{Error}{Code}, $type, $data->{Errors}{Error}{Message},
      )
   });
}

sub _extract_ips {
   my $data = shift;

   map $_->{instancesSet}{item}{ipAddress}, $data->{reservationSet}{item}->@*
}

sub instance_ips {
   my ($self, $args) = @_;

   repeat {
      $self->_delay( after => 2 )
         ->then(sub { $self->describe_instances })
         ->then(sub {
            Future->done(_extract_ips(shift))
         })
   } until => sub {
      my @ips = shift->get;

      scalar @ips == scalar grep $_, @ips
   };
}

sub DEMOLISH {
   my $self = shift;

   $self->_remove_from_loop($self->_ua)
}

1;
