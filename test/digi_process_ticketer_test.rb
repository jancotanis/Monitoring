# frozen_string_literal: true

require 'test_helper'
require 'digi_process_ticketer'

describe DigiProcessTicketer do
  describe '#sanitize' do
    let(:ticketer) { DigiProcessTicketer.allocate }

    it 'leaves short text unchanged' do
      _(ticketer.sanitize('short', 10)).must_equal 'short'
    end

    it 'appends ellipsis when text exceeds max length' do
      _(ticketer.sanitize('a' * 260, 255)).must_equal "#{'a' * 252}..."
    end

    it 'respects the max length including ellipsis' do
      result = ticketer.sanitize('a' * 60_000, 60_000 - 1)
      _(result.length).must_equal 60_000 - 1
      _(result.end_with?('...')).must_equal true
    end

    it 'handles nil input' do
      _(ticketer.sanitize(nil, 255)).must_equal ''
    end

    it 'handles very small max lengths' do
      _(ticketer.sanitize('long text', 2)).must_equal '...'
    end
  end
end
