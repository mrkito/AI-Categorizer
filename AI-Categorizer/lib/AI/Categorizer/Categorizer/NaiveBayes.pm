package AI::Categorizer::Categorizer::NaiveBayes;

use strict;
use AI::Categorizer::Categorizer;
use base qw(AI::Categorizer::Categorizer);
use Params::Validate qw(:types);

__PACKAGE__->valid_params
  (
   bayes_threshold => {type => SCALAR, default => 0.3},
  );

sub create_model {
  my $self = shift;
  my $m = $self->{model} = {};

  my $totaldocs = $self->knowledge->documents;
  $m->{vocab_size} = $self->knowledge->features->length;
  $m->{total_tokens} = $self->knowledge->features->sum;

  # Calculate the probabilities for each category
  foreach my $cat ($self->knowledge->categories) {
    $m->{cat_prob}{$cat->name} = log($cat->documents / $totaldocs);

    # Count the number of tokens in this cat
    $m->{cat_tokens}{$cat->name} = $cat->features->sum;

    my $denominator = log($m->{cat_tokens}{$cat->name} + $m->{vocab_size});

    my $features = $cat->features->as_hash;
    while (my ($feature, $count) = each %$features) {
      $m->{probs}{$cat->name}{$feature} = log($count + 1) - $denominator;
    }
  }
}

# Total number of words (types)  in all docs: (V)        $self->knowledge->features->length or $m->{vocab_size}
# Total number of words (tokens) in all docs:            $self->knowledge->features->sum or $m->{total_tokens}
# Total number of words (types)  in category $c:         $c->features->length
# Total number of words (tokens) in category $c:(N)      $c->features->sum or $m->{cat_tokens}{$c->name}

# Logprobs:
# P($cat) = $m->{cat_prob}{$cat->name}
# P($feature|$cat) = $m->{probs}{$cat->name}{$feature}

sub get_scores {
  my ($self, $newdoc) = @_;
  my $m = $self->{model};  # For convenience
  my $all_features = $self->{knowledge}->features;
  
  # Note that we're using the log(prob) here.  That's why we add instead of multiply.

  my %scores;
  while (my ($cat, $cat_features) = each %{$m->{probs}}) {
    my $fake_prob = -log($m->{cat_tokens}{$cat} + $m->{vocab_size}); # Like a very infrequent word

    $scores{$cat} = $m->{cat_prob}{$cat}; # P($cat)
    
    my $doc_hash = $newdoc->features->as_hash;
    while (my ($feature, $value) = each %$doc_hash) {
      next unless $all_features->includes($feature);
      $scores{$cat} += ($cat_features->{$feature} || $fake_prob)*$value;   # P($feature|$cat)**$value
    }
  }
  
  # Scale everything back to a reasonable area in logspace (near zero), and normalize
  my ($min, $total) = (0, 0);
  foreach (values %scores) { $min = $_ if $_ < $min }
  foreach (keys %scores) {
    $scores{$_} = exp($scores{$_} - $min);
    $total += $scores{$_}**2;
  }
  $total = sqrt($total);
  foreach (keys %scores) {
    $scores{$_} /= $total;
  }
  
  return \%scores;
}

sub categorize {
  my ($self, $doc) = @_;

  my $scores = $self->get_scores($doc);
  
  if ($self->{verbose}) {
    foreach my $key (sort {$scores{$b} <=> $scores{$a}} keys %scores) {
      print "$key: $scores{$key}\n";
    }
  }

  return $self->create_delayed_object('hypothesis',
				      scores => $scores,
				      threshold => $self->{threshold},
				     );
}

1;