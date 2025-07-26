require 'rails_helper'

RSpec.describe 'Api::V1::Relics', type: :request do
  let(:headers) { { 'Content-Type' => 'application/json' } }

  describe 'GET /api/v1/relics' do
    let!(:relics) { create_list(:relic, 5, :with_effects) }
    let!(:attack_relic) { create(:relic, :with_effects, category: 'Attack') }
    let!(:defense_relic) { create(:relic, :with_effects, category: 'Defense') }

    context 'without filters' do
      before { get '/api/v1/relics', headers: headers }

      it 'returns success response' do
        expect_json_response(:ok)
      end

      it 'returns all relics' do
        expect(json_response['data']).to be_an(Array)
        expect(json_response['data'].length).to eq(7) # 5 + 2 specific ones
      end

      it 'includes relic data with effects' do
        relic_data = json_response['data'].first
        expect(relic_data).to include('id', 'name', 'description', 'category', 'rarity', 'effects')
        expect(relic_data['effects']).to be_an(Array)
      end

      it 'includes pagination metadata' do
        expect(json_response['meta']).to include('pagination')
        pagination = json_response['meta']['pagination']
        expect(pagination).to include('current_page', 'per_page', 'total_pages', 'total_count')
      end
    end

    context 'with category filter' do
      before { get '/api/v1/relics?category=Attack', headers: headers }

      it 'returns only attack relics' do
        expect(json_response['data'].all? { |r| r['category'] == 'Attack' }).to be true
      end
    end

    context 'with rarity filter' do
      let!(:common_relic) { create(:relic, :common, :with_effects) }
      let!(:legendary_relic) { create(:relic, :legendary, :with_effects) }

      before { get '/api/v1/relics?rarity=common', headers: headers }

      it 'returns only common relics' do
        expect(json_response['data'].any? { |r| r['rarity'] == 'common' }).to be true
        expect(json_response['data'].none? { |r| r['rarity'] == 'legendary' }).to be true
      end
    end

    context 'with search query' do
      let!(:sword_relic) { create(:relic, :with_effects, name: 'Ancient Sword Power') }

      before { get '/api/v1/relics?search=sword', headers: headers }

      it 'returns relics matching search term' do
        expect(json_response['data'].any? { |r| r['name'].include?('Sword') }).to be true
      end
    end

    context 'with difficulty range' do
      let!(:easy_relic) { create(:relic, :with_effects, obtainment_difficulty: 2) }
      let!(:hard_relic) { create(:relic, :with_effects, obtainment_difficulty: 9) }

      before { get '/api/v1/relics?min_difficulty=1&max_difficulty=5', headers: headers }

      it 'returns relics within difficulty range' do
        difficulties = json_response['data'].map { |r| r['obtainment_difficulty'] }
        expect(difficulties.all? { |d| d >= 1 && d <= 5 }).to be true
      end
    end

    context 'with sorting' do
      before { get '/api/v1/relics?sort_by=obtainment_difficulty&sort_order=desc', headers: headers }

      it 'returns sorted relics' do
        difficulties = json_response['data'].map { |r| r['obtainment_difficulty'] }
        expect(difficulties).to eq(difficulties.sort.reverse)
      end
    end

    context 'with pagination' do
      before { get '/api/v1/relics?page=2&per_page=3', headers: headers }

      it 'returns paginated results' do
        expect(json_response['data'].length).to be <= 3
        expect(json_response['meta']['pagination']['current_page']).to eq(2)
      end
    end
  end

  describe 'GET /api/v1/relics/:id' do
    let(:relic) { create(:relic, :with_effects) }

    context 'when relic exists' do
      before { get "/api/v1/relics/#{relic.id}", headers: headers }

      it 'returns success response' do
        expect_json_response(:ok)
      end

      it 'returns relic data' do
        expect(json_response['data']['id']).to eq(relic.id)
        expect(json_response['data']['name']).to eq(relic.name)
      end

      it 'includes detailed effects information' do
        effects = json_response['data']['effects']
        expect(effects).to be_an(Array)
        expect(effects.first).to include('name', 'effect_type', 'value', 'description')
      end

      it 'includes usage statistics' do
        expect(json_response['data']).to include('usage_statistics')
      end
    end

    context 'when relic does not exist' do
      before { get '/api/v1/relics/non-existent-id', headers: headers }

      it 'returns not found response' do
        expect(response).to have_http_status(:not_found)
        expect_error_response(:not_found, 'Relic not found')
      end
    end
  end

  describe 'POST /api/v1/relics/calculate' do
    let!(:relics) { create_list(:relic, 3, :with_effects) }
    let(:calculation_params) do
      {
        selected_relic_ids: relics.map(&:id),
        context: {
          attack_type: 'normal',
          weapon_type: 'sword',
          enemy_type: 'normal',
          player_level: 50
        },
        options: {
          include_breakdown: true,
          optimization_level: 'basic'
        }
      }
    end

    context 'with valid parameters' do
      before do
        post '/api/v1/relics/calculate',
             params: calculation_params.to_json,
             headers: headers
      end

      it 'returns success response' do
        expect_json_response(:ok)
      end

      it 'returns calculation results' do
        expect(json_response['data']).to include('calculation')
        calculation = json_response['data']['calculation']
        expect(calculation).to include('attack_multipliers', 'efficiency', 'breakdown')
      end

      it 'includes performance metrics' do
        expect(json_response['data']['calculation']['metadata']).to include('performance')
      end
    end

    context 'with invalid relic IDs' do
      before do
        invalid_params = calculation_params.merge(selected_relic_ids: [ 'invalid-id' ])
        post '/api/v1/relics/calculate',
             params: invalid_params.to_json,
             headers: headers
      end

      it 'returns bad request response' do
        expect(response).to have_http_status(:bad_request)
        expect_error_response(:bad_request)
      end
    end

    context 'with missing parameters' do
      before do
        post '/api/v1/relics/calculate',
             params: {}.to_json,
             headers: headers
      end

      it 'returns bad request response' do
        expect(response).to have_http_status(:bad_request)
        expect_error_response(:bad_request, 'selected_relic_ids is required')
      end
    end

    context 'with too many relics' do
      let(:too_many_relics) { create_list(:relic, 15, :with_effects) }

      before do
        invalid_params = calculation_params.merge(selected_relic_ids: too_many_relics.map(&:id))
        post '/api/v1/relics/calculate',
             params: invalid_params.to_json,
             headers: headers
      end

      it 'returns bad request response' do
        expect(response).to have_http_status(:bad_request)
        expect_error_response(:bad_request, 'Maximum 9 relics allowed')
      end
    end
  end

  describe 'POST /api/v1/relics/validate' do
    let!(:relics) { create_list(:relic, 3, :with_effects) }
    let(:validation_params) do
      {
        selected_relic_ids: relics.map(&:id),
        context: {
          combat_style: 'melee'
        }
      }
    end

    context 'with valid relic combination' do
      before do
        post '/api/v1/relics/validate',
             params: validation_params.to_json,
             headers: headers
      end

      it 'returns success response' do
        expect_json_response(:ok)
      end

      it 'returns validation results' do
        expect(json_response['data']).to include('valid')
        expect(json_response['data']['valid']).to be true
      end

      it 'includes validation details' do
        expect(json_response['data']).to include('warnings', 'suggestions')
      end
    end

    context 'with conflicting relics' do
      let!(:relic1) { create(:relic, :with_effects) }
      let!(:relic2) { create(:relic, :with_effects) }

      before do
        relic1.update(conflicts: [ relic2.id ])
        conflicting_params = validation_params.merge(selected_relic_ids: [ relic1.id, relic2.id ])
        post '/api/v1/relics/validate',
             params: conflicting_params.to_json,
             headers: headers
      end

      it 'returns validation with conflicts' do
        expect(json_response['data']['valid']).to be false
        expect(json_response['data']['errors']).to include(match(/conflict/i))
      end
    end
  end

  describe 'POST /api/v1/relics/compare' do
    let!(:relics1) { create_list(:relic, 3, :with_effects) }
    let!(:relics2) { create_list(:relic, 3, :with_effects) }
    let(:compare_params) do
      {
        combinations: [
          {
            name: 'Build A',
            relic_ids: relics1.map(&:id),
            combat_style: 'melee'
          },
          {
            name: 'Build B',
            relic_ids: relics2.map(&:id),
            combat_style: 'melee'
          }
        ]
      }
    end

    context 'with valid combinations' do
      before do
        post '/api/v1/relics/compare',
             params: compare_params.to_json,
             headers: headers
      end

      it 'returns success response' do
        expect_json_response(:ok)
      end

      it 'returns comparison results' do
        expect(json_response['data']).to include('comparisons', 'winner')
        expect(json_response['data']['comparisons']).to be_an(Array)
        expect(json_response['data']['comparisons'].length).to eq(2)
      end

      it 'includes performance metrics for each combination' do
        comparison = json_response['data']['comparisons'].first
        expect(comparison).to include('name', 'attack_multipliers', 'efficiency')
      end
    end

    context 'with insufficient combinations' do
      before do
        invalid_params = compare_params.merge(combinations: [ compare_params[:combinations].first ])
        post '/api/v1/relics/compare',
             params: invalid_params.to_json,
             headers: headers
      end

      it 'returns bad request response' do
        expect(response).to have_http_status(:bad_request)
        expect_error_response(:bad_request, 'At least 2 combinations required for comparison')
      end
    end
  end

  describe 'GET /api/v1/relics/categories' do
    before { get '/api/v1/relics/categories', headers: headers }

    it 'returns success response' do
      expect_json_response(:ok)
    end

    it 'returns all available categories' do
      expect(json_response['data']).to include('Attack', 'Defense', 'Utility', 'Critical', 'Elemental')
    end
  end

  describe 'GET /api/v1/relics/rarities' do
    before { get '/api/v1/relics/rarities', headers: headers }

    it 'returns success response' do
      expect_json_response(:ok)
    end

    it 'returns all available rarities' do
      expect(json_response['data']).to include('common', 'rare', 'epic', 'legendary')
    end
  end

  describe 'error handling' do
    context 'when internal server error occurs' do
      before do
        allow(Relic).to receive(:all).and_raise(StandardError, 'Database error')
        get '/api/v1/relics', headers: headers
      end

      it 'returns internal server error response' do
        expect(response).to have_http_status(:internal_server_error)
        expect_error_response(:internal_server_error)
      end
    end

    context 'with invalid JSON' do
      before do
        post '/api/v1/relics/calculate',
             params: 'invalid json',
             headers: headers
      end

      it 'returns bad request response' do
        expect(response).to have_http_status(:bad_request)
        expect_error_response(:bad_request)
      end
    end
  end

  describe 'caching behavior', :vcr do
    let!(:relic) { create(:relic, :with_effects) }

    it 'caches relic show responses' do
      # First request
      get "/api/v1/relics/#{relic.id}", headers: headers
      expect(response.headers['X-Cache-Status']).to eq('MISS')

      # Second request should be cached
      get "/api/v1/relics/#{relic.id}", headers: headers
      expect(response.headers['X-Cache-Status']).to eq('HIT')
    end
  end

  describe 'rate limiting' do
    it 'enforces rate limits on calculation endpoint' do
      relics = create_list(:relic, 3, :with_effects)
      calculation_params = {
        selected_relic_ids: relics.map(&:id),
        context: { attack_type: 'normal' }
      }

      # Make requests up to the limit
      20.times do
        post '/api/v1/relics/calculate',
             params: calculation_params.to_json,
             headers: headers
      end

      expect(response).to have_http_status(:ok)

      # Next request should be rate limited
      post '/api/v1/relics/calculate',
           params: calculation_params.to_json,
           headers: headers

      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
