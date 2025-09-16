# Shared Services

Cross-cutting services.

- `encryption_service.dart`: Device-specific key management; handles corrupted values by reset + regenerate
- `secure_env_service.dart`: Bootstraps secure configuration

Notes
- Uses `flutter_secure_storage`
- Catch `PlatformException` to recover from `BadPaddingException`


