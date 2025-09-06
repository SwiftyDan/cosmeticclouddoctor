import Foundation

// MARK: - User API Service
class UserAPIService {
    private let apiService: APIService
    private let keychainService: KeychainServiceProtocol

    init(apiService: APIService = APIService(),
         keychainService: KeychainServiceProtocol = KeychainService()) {
        self.apiService = apiService
        self.keychainService = keychainService
    }

    func deactivateAccount() async throws -> EmptyResponse {
        guard let authToken = keychainService.retrieve(key: "auth_token", type: String.self) else {
            throw NetworkError.unauthorized
        }
        let url = APIConfiguration.shared.endpoints.deleteUser
        let response: EmptyResponse = try await apiService.delete(
            endpoint: url,
            authToken: authToken,
            configuration: .default,
            responseType: EmptyResponse.self
        )
        return response
    }
}


