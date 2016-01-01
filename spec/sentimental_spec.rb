require_relative '../lib/sentimental'

describe Sentimental do
  let(:root) { File.expand_path(File.join(File.dirname(__FILE__), '..')) }
  let(:loader) { Sentimental.new(threshold: 0.1) }

  describe '#load_defaults' do
    it 'loads words and influencers' do
      senti_en_words = "#{root}/data/en_words.json"
      senti_fr_words = "#{root}/data/fr_words.json"
      sentislang = "#{root}/data/slang.json"
      influencers = "#{root}/data/influencers.json"
      en_words_count = JSON.load(File.open(senti_en_words)).keys.count
      fr_words_count = JSON.load(File.open(senti_fr_words)).keys.count
      slang_count = JSON.load(File.open(sentislang)).keys.count
      influence_count = JSON.load(File.open(influencers)).keys.count

      loader.load_defaults

      expect(loader.word_scores.count).to eq en_words_count + fr_words_count + slang_count
      expect(loader.influencers.count).to eq influence_count
    end
  end

  describe '#load_from_json' do
    it 'loads word_scores' do
      filename = "#{root}/data/slang.json"
      loader.load_from_json(filename)
      slang_count = JSON.load(File.open(filename)).keys.count
      expect(loader.word_scores.count).to eq slang_count
      expect(loader.influencers.count).to eq 0
    end
  end

  describe '#load_influencers' do
    it 'loads influencers' do
      filename = "#{root}/data/influencers.json"
      loader.load_influencers_from_json(filename)
      count = JSON.load(File.open(filename)).keys.count

      expect(loader.word_scores.count).to eq 0
      expect(loader.influencers.count).to eq count
    end
  end

  let(:analyzer) { Sentimental.new(threshold: 0.1) }
  before :each do
    analyzer.load_defaults
  end

  describe '#sentiment' do
    it 'returns :positive when the score > threshold' do
      expect(analyzer.sentiment('I love ruby <3')).to be :positive
    end

    it 'returns :negative when the score < -threshold' do
      expect(analyzer.sentiment('I hate javascript')).to be :negative
    end

    it 'returns :neutral when -threshold < score < threshold' do
      expect(analyzer.sentiment("I don't know")).to be :neutral
    end

    it 'returns :positive when the score > threshold (even in french ;-)' do
      expect(analyzer.sentiment("J'adore le ruby <3")).to be :positive
    end
  end

  describe '#classify' do
    it 'is true when in the class' do
      expect(analyzer.classify('I love ruby')).to be_truthy
    end

    it 'is false otherwise' do
      expect(analyzer.classify('je ne sais pas')).to be_falsy
      expect(analyzer.classify('i hate java')).to be_falsy
    end
  end

  describe 'initialization' do
    subject do
      Sentimental.new(
        threshold: 0.2,
        word_scores: { 'non' => -1.0 },
        neutral_regexps: [/.*/]
      )
    end

    it 'takes multiple init params' do
      expect(subject.threshold).to eq 0.2
      expect(subject.word_scores['non']).to eq(-1.0)
      expect(subject.neutral_regexps).to include(/.*/)
    end
  end

  describe 'neutral regexp' do
    context 'when there is some neutral regexp' do
      let(:en_text_neutral) { 'Do you love ruby?' }
      let(:en_text) { 'I love ruby' }
      let(:fr_text_neutral) { 'Êtes-vous amoureux de ruby?' }
      let(:fr_text) { "J'adore ruby <3" }

      before do
        analyzer.neutral_regexps << /\?\s*$/
      end

      it 'scores it to 0' do
        expect(analyzer.score(en_text_neutral)).to eq 0
        expect(analyzer.score(en_text)).not_to eq 0
        expect(analyzer.score(fr_text_neutral)).to eq 0
        expect(analyzer.score(fr_text)).not_to eq 0
      end
    end
  end

  describe 'n-grams' do
    let(:word_scores) { nil }
    subject do
      Sentimental.new(word_scores: word_scores, ngrams: 3)
    end

    it 'is initialized by ngrams param' do
      expect(subject.ngrams).to eq 3
    end

    context 'there is n-grams in the dictionary' do
      let(:word_scores) { { 'happy hour' => 1.0, 'not happy hour' => -5.0 } }
      let(:text) { 'why not happy hour, but happy so hour?' }

      it 'update scores regarding to n-grams' do
        expect(subject.score(text)).to eq(-4)
      end
    end

    context "there's n-grams longer than specified in dictionary" do
      let(:word_scores) { { 'happy hour' => 1.0, 'not so happy hour' => -5.0 } }
      let(:text) { 'why not so happy hour ?' }

      it 'ignores the lines' do
        expect(subject.score(text)).to eq 1
      end
    end
  end

  describe 'scoring in a normal context' do
    subject do
      analyzer.score(text)
    end

    context 'when the text is positive' do
      let(:text) { 'I love ruby' }

      it 'returns a positive score' do
        expect(subject).to be > 0
      end
    end

    context 'when the text is neutral' do
      let(:text) { 'I like ruby' }

      it 'returns a neutral score' do
        expect(subject).to eq 0
      end
    end

    context 'when the text is negative' do
      let(:text) { 'I hate ruby' }

      it 'returns a negative score' do
        expect(subject).to be < 0
      end
    end

    context 'when the text has smiley' do
      let(:text) { 'I love ruby' }
      let(:text_with_smiley) { 'I love ruby :-)' }

      it 'scores it' do
        expect(analyzer.score(text_with_smiley)).to be > analyzer.score(text)
      end
    end

    context 'when the text has punctuation' do
      let(:text) { 'I love ruby' }
      let(:text_with_punctuation) { 'I love, ruby' }

      it 'removes it' do
        expect(analyzer.score(text_with_punctuation)).to eq analyzer.score(text)
      end
    end
  end

  describe 'influencers' do
    let(:positive) { 'I love open source project' }
    let(:positive_influence) { 'I really love open source project' }
    let(:neutral) { 'Ruby is cool' }
    let(:neutral_influence) { 'Ruby is really cool' }
    let(:negative) { 'I hate this' }
    let(:negative_influence) { 'I really hate this' }

    it 'influences positively' do
      expect(analyzer.score(positive_influence)).to be > analyzer.score(positive)
    end

    it 'influence positively for neutral' do
      expect(analyzer.score(neutral_influence)).to eq analyzer.score(neutral)
    end

    it 'influences negatively' do
      expect(analyzer.score(negative_influence)).to be < analyzer.score(negative)
    end

    it 'multiplies next word only and not the whole sentence' do
      expect(analyzer.score('i really love ruby, but i hate and hate and hate and hate MRI implem'))
        .to be > analyzer.score('i love ruby, but i hate and hate and hate and hate MRI implem')
    end

    it 'it multiplies influencing words' do
      expect(analyzer.score('I really really love ruby'))
        .to be > analyzer.score('I really love ruby')
    end
  end
  describe 'influencers (in french ;-)' do
    let(:positive) { 'Je suis admiratif des projets open-source :)' }
    let(:positive_influence) { 'Je suis vraiment admiratif des projets open-source :)' }
    let(:neutral) { "Ruby c'est cool" }
    let(:neutral_influence) { "Ruby c'est vraiment cool" }
    let(:negative) { "ruby c'est nul, c'est pas bien" }
    let(:negative_influence) { "ruby c'est nul, c'est vraiment pas bien" }

    it 'influences positively' do
      expect(analyzer.score(positive_influence)).to be > analyzer.score(positive)
    end

    it 'influence positively for neutral' do
      expect(analyzer.score(neutral_influence)).to eq analyzer.score(neutral)
    end

    it 'influences negatively' do
      expect(analyzer.score(negative_influence)).to be < analyzer.score(negative)
    end

    it 'multiplies next word only and not the whole sentence' do
      # FIXME
      # expect(analyzer.score("J'adore le ruby <3, mais j'aime pas et j'aime pas les implémentations en MRI"))
      #   .to be > analyzer.score("J'adore le ruby, mais j'aime pas et j'aime pas les implémentations en MRI")
    end

    it 'it multiplies influencing words' do
      expect(analyzer.score('Je suis vraiment vraiment amoureux de ruby'))
        .to be > analyzer.score('Je suis vraiment amoureux de ruby')
    end
  end
end
