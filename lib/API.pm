package
   API;

use Moo;

use experimental 'postderef';

use VM::EC2;
use Future;
use Future::Utils 'repeat';
use Try::Tiny;


has _ec2 => (
   is => 'ro',
   lazy => 1,
   builder => sub {
      VM::EC2->new(
         -access_key => 'AKIAIX4VB7VY7DHWNYCA',
         -secret_key => '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',
         -endpoint   => 'https://ec2.us-west-2.amazonaws.com',
      );
   },
);

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

1;
