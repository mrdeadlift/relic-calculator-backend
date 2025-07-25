module Request
  module JsonHelpers
    def json_response
      @json_response ||= JSON.parse(response.body)
    end

    def json_response_symbolized
      @json_response_symbolized ||= JSON.parse(response.body, symbolize_names: true)
    end
  end
end

module Response
  module JsonHelpers
    def expect_json_response(status = :ok)
      expect(response).to have_http_status(status)
      expect(response.content_type).to eq('application/json; charset=utf-8')
    end

    def expect_error_response(status, message = nil)
      expect(response).to have_http_status(status)
      expect(json_response['error']).to be_present
      expect(json_response['error']['message']).to eq(message) if message
    end

    def expect_success_response(status = :ok)
      expect(response).to have_http_status(status)
      expect(json_response['success']).to be_truthy
    end
  end
end