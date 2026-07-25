# frozen_string_literal: true

require 'test_helper'

# Every locale file must carry exactly the keys English does, with the same
# %{...} interpolation tokens — a missing key silently falls back to English,
# and a missing token breaks the string at runtime.
class LocalesTest < ActiveSupport::TestCase
  LOCALE_DIR = File.expand_path('../config/locales', __dir__)

  def flatten(hash, prefix = [])
    hash.flat_map do |key, value|
      value.is_a?(Hash) ? flatten(value, prefix + [key]) : [(prefix + [key]).join('.')]
    end
  end

  def load_locale(path)
    data = YAML.safe_load_file(path)
    locale = data.keys.first
    [locale, data.fetch(locale).fetch('livechat')]
  end

  test 'all locales have the same keys as English' do
    en_path = File.join(LOCALE_DIR, 'livechat.en.yml')
    _, en = load_locale(en_path)
    en_keys = flatten(en).sort

    Dir[File.join(LOCALE_DIR, 'livechat.*.yml')].each do |path|
      locale, translations = load_locale(path)
      assert_equal en_keys, flatten(translations).sort,
                   "#{locale} keys diverge from English"
    end
  end

  test 'interpolation tokens survive translation' do
    en_path = File.join(LOCALE_DIR, 'livechat.en.yml')
    _, en = load_locale(en_path)
    tokens = ->(string) { string.to_s.scan(/%\{[^}]+\}/).sort }

    en_flat = {}
    walk = lambda do |hash, prefix|
      hash.each do |key, value|
        if value.is_a?(Hash) then walk.call(value, prefix + [key])
        else en_flat[(prefix + [key]).join('.')] = value
        end
      end
    end
    walk.call(en, [])

    Dir[File.join(LOCALE_DIR, 'livechat.*.yml')].each do |path|
      locale, translations = load_locale(path)
      flat = {}
      walk_t = lambda do |hash, prefix|
        hash.each do |key, value|
          if value.is_a?(Hash) then walk_t.call(value, prefix + [key])
          else flat[(prefix + [key]).join('.')] = value
          end
        end
      end
      walk_t.call(translations, [])

      en_flat.each do |key, english|
        next unless flat.key?(key)

        assert_equal tokens.call(english), tokens.call(flat[key]),
                     "#{locale} #{key} interpolation tokens diverge"
      end
    end
  end
end
