# Data Layer

Services and models for backend interaction using Dio.

Key components
- `auth_api.dart`: Dio instance with interceptors for Authorization header and automatic refresh on 401
- `api_service.dart`: High-level API calls (records, custom emotions, chat)
- `models/`: DTOs and entities

Testing
```bash
flutter test -r expanded
```
Uses `http_mock_adapter` and `mocktail`.


