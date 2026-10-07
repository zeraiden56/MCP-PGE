# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/mock'

load File.expand_path('../bin/smoke_all_tribunais', __dir__)

class SmokeAllTribunaisTest < Minitest::Test
  class Repository < TestData::MemoryRepository
    attr_reader :closed

    def close
      @closed = true
    end
  end

  def inputs
    {
      'TRF1_CNJ' => cnj,
      'TJMT_CNJ' => cnj('8', '11', '0001'),
      'STJ_CNJ' => cnj('3', '00', '0000'),
      'STF_CNJ' => cnj('1', '00', '0000')
    }
  end

  def run_matrix(responses:, env: inputs, argv: [])
    @out = StringIO.new
    @err = StringIO.new
    @repo = Repository.new
    @http = FakeHTTP.new(*responses)

    config = Juridico::Config.new(
      'DATABASE_URL' => 'test-only',
      'CACHE_TTL_SECONDS' => '0'
    )

    builds = 0

    factory = lambda do |**|
      builds += 1
      @repo
    end

    result = nil

    Juridico.stub(
      :server,
      ->(**) { flunk 'Não deve construir MCP' }
    ) do
      Juridico::Config.stub(:new, config) do
        Juridico::Telemetry.stub(:new, telemetry) do
          Juridico::HttpClient.stub(:new, @http) do
            Repositories::ProcessoRepository.stub(:new, factory) do
              result =
                Juridico::SmokeAllTribunais.run(
                  argv,
                  env: env,
                  out: @out,
                  err: @err
                )
            end
          end
        end
      end
    end

    assert_equal 1, builds
    assert @repo.closed

    result
  end

  def rows
    @out.string.lines.drop(2).to_h do |line|
      values =
        line
          .strip
          .split(/\s*\|\s*/)

      row =
        Juridico::SmokeAllTribunais::COLUMNS
          .zip(values)
          .to_h

      [row[:tribunal], row]
    end
  end

  def test_full_matrix_real_composition_and_unsupported_stf
    assert_equal(
      0,
      run_matrix(
        responses: [
          fixture,
          fixture('TJMT'),
          fixture('STJ')
        ]
      )
    )

    assert_equal(
      Tribunais::TribunalResolver::ORIGENS.values.uniq,
      rows.keys
    )

    %w[TRF1 TJMT STJ].each do |tribunal|
      row = rows.fetch(tribunal)

      assert_equal 'ok', row[:status]
      assert_equal 'datajud', row[:fonte]
      assert_equal 'miss', row[:cache]
      assert_equal '1', row[:processos_encontrados]
      assert_equal '1', row[:movimentacoes_encontradas]

      refute_equal '-', row[:consultado_em]
    end

    stf = rows.fetch('STF')

    assert_equal 'unsupported', stf[:status]
    assert_equal 'unsupported_tribunal', stf[:code]
    assert_equal '-', stf[:fonte]
    assert_equal '-', stf[:cache]
    assert_equal '-', stf[:processos_encontrados]
    assert_equal '-', stf[:movimentacoes_encontradas]

    assert_equal 3, @http.calls.size
    assert_equal 3, @repo.audits.size

    refute_includes @out.string, 'Unidade fictícia'
  end

  def test_error_codes_are_distinct_and_remaining_courts_continue
    %w[
      not_found
      incomplete_response
      upstream_timeout
      upstream_http_error
    ].each do |code|
      failure =
        Juridico::Error.new(
          code,
          'SECRET postgresql://PRIVATE CPF 12345678900'
        )

      assert_equal(
        1,
        run_matrix(
          responses: [
            failure,
            fixture('TJMT'),
            fixture('STJ')
          ]
        )
      )

      assert_equal code, rows['TRF1'][:code]
      assert_equal 'error', rows['TRF1'][:status]
      assert_equal 'datajud', rows['TRF1'][:fonte]

      assert_equal 'ok', rows['TJMT'][:status]
      assert_equal 'ok', rows['STJ'][:status]

      assert_equal 3, @http.calls.size

      %w[
        SECRET
        PRIVATE
        CPF
        12345678900
      ].each do |secret|
        refute_includes(
          @out.string + @err.string,
          secret
        )
      end
    end
  end

  def test_partial_response_is_not_persisted_and_no_extra_retry_occurs
    partial = fixture

    partial['_shards']['failed'] = 1

    assert_equal(
      1,
      run_matrix(
        responses: [partial],
        env: {
          'TRF1_CNJ' => cnj
        }
      )
    )

    assert_equal(
      'incomplete_response',
      rows['TRF1'][:code]
    )

    assert_equal(
      'error',
      rows['TRF1'][:status]
    )

    assert_empty @repo.data

    assert_equal(
      'error',
      @repo.audits.first[:status]
    )

    assert_equal 1, @http.calls.size
  end

  def test_arguments_override_environment_and_omissions_are_skipped
    assert_equal(
      0,
      run_matrix(
        responses: [fixture],
        env: {
          'TRF1_CNJ' => 'SECRET'
        },
        argv: [
          "TRF1_CNJ=#{cnj}"
        ]
      )
    )

    assert_equal(
      'ok',
      rows['TRF1'][:status]
    )

    assert_equal(
      'skipped',
      rows['TJMT'][:status]
    )

    assert_equal(
      'missing_cnj',
      rows['TJMT'][:code]
    )

    refute_includes(
      @out.string,
      'SECRET'
    )
  end

  def test_wrong_origin_and_invalid_input_do_not_query_source
    env = {
      'TRF1_CNJ' => inputs['TJMT_CNJ'],
      'STJ_CNJ' => 'SECRET',
      'TJMT_CNJ' => inputs['TJMT_CNJ']
    }

    assert_equal(
      1,
      run_matrix(
        responses: [
          fixture('TJMT')
        ],
        env: env
      )
    )

    assert_equal(
      'tribunal_mismatch',
      rows['TRF1'][:code]
    )

    assert_equal(
      'error',
      rows['TRF1'][:status]
    )

    assert_equal(
      'invalid_cnj',
      rows['STJ'][:code]
    )

    assert_equal(
      'error',
      rows['STJ'][:status]
    )

    assert_equal(
      'ok',
      rows['TJMT'][:status]
    )

    assert_equal 1, @http.calls.size

    refute_includes(
      @out.string,
      'SECRET'
    )
  end

  def test_no_inputs_does_not_build
    @out = StringIO.new
    @err = StringIO.new

    Juridico.stub(
      :build_service,
      -> { flunk 'Não deve conectar banco' }
    ) do
      assert_equal(
        2,
        Juridico::SmokeAllTribunais.run(
          [],
          env: {},
          out: @out,
          err: @err
        )
      )
    end

    #
    # A versão atual retorna usage antes de
    # imprimir a matriz quando nenhum CNJ
    # é informado.
    #
    assert_includes(
      @err.string,
      'Uso:'
    )
  end

  def test_build_failure_still_prints_all_rows_without_secrets
    @out = StringIO.new
    @err = StringIO.new

    Juridico.stub(
      :build_service,
      lambda {
        raise Juridico::Error.new(
          'database_error',
          'SECRET'
        )
      }
    ) do
      assert_equal(
        1,
        Juridico::SmokeAllTribunais.run(
          [],
          env: inputs,
          out: @out,
          err: @err
        )
      )
    end

    assert_equal(
      4,
      rows.size
    )

    assert(
      rows.values.all? do |row|
        row[:code] == 'database_error'
      end
    )

    assert(
      rows.values.all? do |row|
        row[:status] == 'error'
      end
    )

    refute_includes(
      @out.string + @err.string,
      'SECRET'
    )
  end
end