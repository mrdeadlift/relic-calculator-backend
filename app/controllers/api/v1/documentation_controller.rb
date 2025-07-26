class Api::V1::DocumentationController < Api::V1::BaseController
  # GET /api/v1/documentation
  def index
    render_success(
      {
        api_info: {
          title: "Nightreign Relic Calculator API",
          version: "v1",
          description: "RESTful API for calculating attack multipliers when combining Elden Ring Nightreign relics",
          base_url: Rails.application.config.api_base_url,
          contact: {
            name: "API Support",
            email: "support@nightreign-calculator.com"
          }
        },
        endpoints: generate_endpoint_documentation,
        response_format: generate_response_format_documentation,
        error_codes: generate_error_codes_documentation,
        examples: generate_examples_documentation
      },
      message: "API documentation retrieved successfully"
    )
  end

  # GET /api/v1/documentation/openapi.json
  def openapi_spec
    render json: generate_openapi_spec
  end

  # GET /api/v1/documentation/postman
  def postman_collection
    render json: generate_postman_collection
  end

  private

  def generate_endpoint_documentation
    {
      relics: {
        base_path: "/api/v1/relics",
        endpoints: [
          {
            method: "GET",
            path: "/api/v1/relics",
            description: "Get paginated list of relics with filtering and search",
            parameters: [
              { name: "page", type: "integer", description: "Page number (default: 1)" },
              { name: "per_page", type: "integer", description: "Items per page (default: 20, max: 100)" },
              { name: "search", type: "string", description: "Search in name and description" },
              { name: "category", type: "string", description: "Filter by category" },
              { name: "rarity", type: "string", description: "Filter by rarity" },
              { name: "sort_by", type: "string", description: "Sort by: name, rarity, difficulty, created_at" }
            ]
          },
          {
            method: "GET",
            path: "/api/v1/relics/:id",
            description: "Get detailed information about a specific relic",
            parameters: [
              { name: "id", type: "string", description: "Relic ID", required: true }
            ]
          },
          {
            method: "POST",
            path: "/api/v1/relics/calculate",
            description: "Calculate attack multiplier for a combination of relics",
            parameters: [
              { name: "relic_ids", type: "array", description: "Array of relic IDs", required: true },
              { name: "combat_style", type: "string", description: "Combat style: melee, ranged, magic, hybrid" },
              { name: "character_level", type: "integer", description: "Character level (1-999)" },
              { name: "weapon_type", type: "string", description: "Weapon type for conditional effects" }
            ]
          }
        ]
      },
      optimization: {
        base_path: "/api/v1/optimization",
        endpoints: [
          {
            method: "POST",
            path: "/api/v1/optimization/suggest",
            description: "Get optimization suggestions for improving a build",
            parameters: [
              { name: "relic_ids", type: "array", description: "Current relic IDs", required: true },
              { name: "combat_style", type: "string", description: "Combat style preference" },
              { name: "max_difficulty", type: "integer", description: "Maximum obtainment difficulty" }
            ]
          },
          {
            method: "POST",
            path: "/api/v1/optimization/analyze",
            description: "Analyze a build and provide detailed performance metrics",
            parameters: [
              { name: "relic_ids", type: "array", description: "Relic IDs to analyze", required: true }
            ]
          }
        ]
      },
      builds: {
        base_path: "/api/v1/builds",
        endpoints: [
          {
            method: "GET",
            path: "/api/v1/builds",
            description: "Get paginated list of builds",
            parameters: [
              { name: "combat_style", type: "string", description: "Filter by combat style" },
              { name: "visibility", type: "string", description: "Filter by public/private" }
            ]
          },
          {
            method: "POST",
            path: "/api/v1/builds",
            description: "Create a new build",
            parameters: [
              { name: "name", type: "string", description: "Build name", required: true },
              { name: "description", type: "string", description: "Build description" },
              { name: "combat_style", type: "string", description: "Combat style", required: true },
              { name: "relic_ids", type: "array", description: "Initial relic IDs" }
            ]
          }
        ]
      }
    }
  end

  def generate_response_format_documentation
    {
      success_response: {
        description: "Standard successful response format",
        structure: {
          success: "boolean - Always true for successful responses",
          message: "string - Human-readable success message",
          data: "object/array - Response payload data",
          meta: {
            timestamp: "string - ISO8601 timestamp of response",
            request_id: "string - Unique request identifier",
            version: "string - API version",
            pagination: "object - Pagination info (when applicable)"
          }
        }
      },
      error_response: {
        description: "Standard error response format",
        structure: {
          success: "boolean - Always false for error responses",
          message: "string - Human-readable error message",
          error_code: "string - Machine-readable error code",
          details: "object - Additional error details and context",
          meta: {
            timestamp: "string - ISO8601 timestamp of response",
            request_id: "string - Unique request identifier",
            version: "string - API version"
          }
        }
      },
      pagination: {
        description: "Pagination metadata structure",
        structure: {
          current_page: "integer - Current page number",
          per_page: "integer - Items per page",
          total_pages: "integer - Total number of pages",
          total_count: "integer - Total number of items",
          has_next_page: "boolean - Whether next page exists",
          has_prev_page: "boolean - Whether previous page exists"
        }
      }
    }
  end

  def generate_error_codes_documentation
    {
      validation_errors: {
        "REQUIRED_PARAMETER_MISSING" => "A required parameter is missing from the request",
        "INVALID_PARAMETER_FORMAT" => "A parameter has an invalid format or value",
        "PARAMETER_OUT_OF_RANGE" => "A numeric parameter is outside the allowed range",
        "INVALID_ENUM_VALUE" => "A parameter value is not in the allowed set of values",
        "ARRAY_TOO_LARGE" => "An array parameter exceeds the maximum allowed size"
      },
      business_logic_errors: {
        "RELIC_NOT_FOUND" => "One or more relic IDs do not exist",
        "CONFLICTING_RELICS" => "Selected relics have conflicts and cannot be used together",
        "RELIC_LIMIT_EXCEEDED" => "Too many relics selected (max 9 per build)",
        "CALCULATION_TIMEOUT" => "Calculation took too long and was terminated",
        "OPTIMIZATION_TIMEOUT" => "Optimization process timed out"
      },
      system_errors: {
        "RATE_LIMIT_EXCEEDED" => "Too many requests from this IP address",
        "REQUEST_BLOCKED" => "Request blocked due to suspicious activity",
        "INTERNAL_SERVER_ERROR" => "An unexpected server error occurred"
      }
    }
  end

  def generate_examples_documentation
    {
      calculate_request: {
        method: "POST",
        url: "/api/v1/relics/calculate",
        headers: {
          "Content-Type" => "application/json"
        },
        body: {
          relic_ids: [ "physical-attack-up", "improved-straight-sword", "initial-attack-buff" ],
          combat_style: "melee",
          character_level: 50,
          weapon_type: "straight_sword"
        }
      },
      calculate_response: {
        success: true,
        message: "Attack multiplier calculated successfully",
        data: {
          total_multiplier: 2.45,
          base_multiplier: 1.0,
          stacking_bonuses: [
            {
              effect_name: "Physical Attack Up",
              relic_name: "Physical Attack Up",
              base_value: 15.0,
              stacked_value: 15.0,
              stacking_rule: "additive"
            }
          ],
          conditional_effects: [],
          final_attack_power: 245.0,
          breakdown: [
            {
              step: 1,
              description: "Base attack power",
              operation: "base",
              value: 100.0,
              running_total: 100.0
            }
          ]
        },
        meta: {
          timestamp: "2024-01-15T10:30:00Z",
          request_id: "req_123456789",
          version: "v1",
          calculation_context: {
            combatStyle: "melee",
            characterLevel: 50,
            weaponType: "straight_sword"
          }
        }
      },
      optimization_request: {
        method: "POST",
        url: "/api/v1/optimization/suggest",
        headers: {
          "Content-Type" => "application/json"
        },
        body: {
          relic_ids: [ "physical-attack-up", "improved-straight-sword" ],
          combat_style: "melee",
          max_difficulty: 7,
          prefer_high_rarity: false
        }
      },
      build_creation_request: {
        method: "POST",
        url: "/api/v1/builds",
        headers: {
          "Content-Type" => "application/json"
        },
        body: {
          name: "High DPS Melee Build",
          description: "A build focused on maximizing melee damage output",
          combat_style: "melee",
          is_public: true,
          relic_ids: [ "physical-attack-up", "improved-straight-sword", "initial-attack-buff" ]
        }
      }
    }
  end

  def generate_openapi_spec
    {
      openapi: "3.0.0",
      info: {
        title: "Nightreign Relic Calculator API",
        version: "v1",
        description: "API for calculating attack multipliers when combining Elden Ring Nightreign relics",
        contact: {
          name: "API Support",
          email: "support@nightreign-calculator.com"
        }
      },
      servers: [
        {
          url: Rails.application.config.api_base_url,
          description: "Main API server"
        }
      ],
      paths: generate_openapi_paths,
      components: {
        schemas: generate_openapi_schemas,
        responses: generate_openapi_responses
      }
    }
  end

  def generate_openapi_paths
    {
      "/api/v1/relics" => {
        get: {
          summary: "List relics",
          parameters: [
            {
              name: "page",
              in: "query",
              schema: { type: "integer", minimum: 1 }
            },
            {
              name: "per_page",
              in: "query",
              schema: { type: "integer", minimum: 1, maximum: 100 }
            }
          ],
          responses: {
            "200" => { "$ref" => "#/components/responses/RelicList" }
          }
        }
      },
      "/api/v1/relics/calculate" => {
        post: {
          summary: "Calculate attack multiplier",
          requestBody: {
            required: true,
            content: {
              "application/json" => {
                schema: { "$ref" => "#/components/schemas/CalculationRequest" }
              }
            }
          },
          responses: {
            "200" => { "$ref" => "#/components/responses/CalculationResult" },
            "400" => { "$ref" => "#/components/responses/ValidationError" }
          }
        }
      }
    }
  end

  def generate_openapi_schemas
    {
      CalculationRequest: {
        type: "object",
        required: [ "relic_ids" ],
        properties: {
          relic_ids: {
            type: "array",
            items: { type: "string" },
            maxItems: 9
          },
          combat_style: {
            type: "string",
            enum: [ "melee", "ranged", "magic", "hybrid" ]
          },
          character_level: {
            type: "integer",
            minimum: 1,
            maximum: 999
          }
        }
      },
      Relic: {
        type: "object",
        properties: {
          id: { type: "string" },
          name: { type: "string" },
          description: { type: "string" },
          category: { type: "string" },
          rarity: { type: "string" },
          quality: { type: "string" },
          obtainment_difficulty: { type: "integer" }
        }
      }
    }
  end

  def generate_openapi_responses
    {
      RelicList: {
        description: "List of relics with pagination",
        content: {
          "application/json" => {
            schema: {
              type: "object",
              properties: {
                success: { type: "boolean" },
                message: { type: "string" },
                data: {
                  type: "array",
                  items: { "$ref" => "#/components/schemas/Relic" }
                }
              }
            }
          }
        }
      },
      ValidationError: {
        description: "Validation error response",
        content: {
          "application/json" => {
            schema: {
              type: "object",
              properties: {
                success: { type: "boolean", example: false },
                message: { type: "string" },
                error_code: { type: "string" },
                details: { type: "object" }
              }
            }
          }
        }
      }
    }
  end

  def generate_postman_collection
    {
      info: {
        name: "Nightreign Relic Calculator API",
        schema: "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
      },
      variable: [
        {
          key: "baseUrl",
          value: Rails.application.config.api_base_url
        }
      ],
      item: [
        {
          name: "Relics",
          item: [
            {
              name: "List Relics",
              request: {
                method: "GET",
                header: [],
                url: {
                  raw: "{{baseUrl}}/api/v1/relics?page=1&per_page=20",
                  host: [ "{{baseUrl}}" ],
                  path: [ "api", "v1", "relics" ],
                  query: [
                    { key: "page", value: "1" },
                    { key: "per_page", value: "20" }
                  ]
                }
              }
            },
            {
              name: "Calculate Attack Multiplier",
              request: {
                method: "POST",
                header: [
                  {
                    key: "Content-Type",
                    value: "application/json"
                  }
                ],
                body: {
                  mode: "raw",
                  raw: JSON.pretty_generate({
                    relic_ids: [ "physical-attack-up", "improved-straight-sword" ],
                    combat_style: "melee",
                    character_level: 50
                  })
                },
                url: {
                  raw: "{{baseUrl}}/api/v1/relics/calculate",
                  host: [ "{{baseUrl}}" ],
                  path: [ "api", "v1", "relics", "calculate" ]
                }
              }
            }
          ]
        }
      ]
    }
  end
end
