# frozen_string_literal: true

require 'openssl'

module Zip
  module AESEncryption # :nodoc:
    VERIFIER_LENGTH = 2
    BLOCK_SIZE = 16
    AUTHENTICATION_CODE_LENGTH = 10

    VERSION_AE_1 = 0x01
    VERSION_AE_2 = 0x02

    VERSIONS = [
      VERSION_AE_1,
      VERSION_AE_2
    ]

    STRENGTH_128_BIT = 0x01
    STRENGTH_192_BIT = 0x02
    STRENGTH_256_BIT = 0x03

    STRENGTHS = [
      STRENGTH_128_BIT,
      STRENGTH_192_BIT,
      STRENGTH_256_BIT
    ]

    BITS = {
      STRENGTH_128_BIT => 128,
      STRENGTH_192_BIT => 192,
      STRENGTH_256_BIT => 256
    }

    KEY_LENGTHS = {
      STRENGTH_128_BIT => 16,
      STRENGTH_192_BIT => 24,
      STRENGTH_256_BIT => 32,
    }

    SALT_LENGTHS = {
      STRENGTH_128_BIT => 8,
      STRENGTH_192_BIT => 12,
      STRENGTH_256_BIT => 16,
    }

    def initialize(password, strength)
      @password = password
      @strength = strength
      @bits = BITS[@strength]
      @key_length = KEY_LENGTHS[@strength]
      @salt_length = SALT_LENGTHS[@strength]
      @counter = 0
    end

    def header_bytesize
      @salt_length + VERIFIER_LENGTH
    end

    def gp_flags
      0x0001
    end
  end

  class AESDecrypter < Decrypter # :nodoc:
    include AESEncryption

    def decrypt(encrypted_data)
      amount_to_read = encrypted_data.size
      decrypted_data = +''

      while amount_to_read > 0
        @cipher.iv = [@counter + 1].pack('Vx12')
        begin_index = BLOCK_SIZE * @counter
        end_index = BLOCK_SIZE * @counter + [BLOCK_SIZE, amount_to_read].min - 1
        decrypted_data << @cipher.update(encrypted_data[begin_index..end_index])
        amount_to_read -= BLOCK_SIZE
        @counter += 1
      end

      decrypted_data
    end

    def reset!(header)
      raise Error, "Unsupported encryption AES-#{@bits}" unless STRENGTHS.include? @strength

      salt = header[0..@salt_length - 1]
      pwd_verify = header[-VERIFIER_LENGTH..-1]
      key_material = OpenSSL::PKCS5.pbkdf2_hmac_sha1(@password, salt, 1000, 2 * @key_length + VERIFIER_LENGTH)
      enc_key = key_material[0..@key_length - 1]
      enc_hmac_key = key_material[@key_length..2 * @key_length - 1]
      enc_pwd_verify = key_material[-VERIFIER_LENGTH..-1]

      raise Error, 'Bad password' if enc_pwd_verify != pwd_verify

      @counter = 0
      @cipher = OpenSSL::Cipher::AES.new(@bits, :CTR)
      @cipher.decrypt
      @cipher.key = enc_key
    end
  end
end
