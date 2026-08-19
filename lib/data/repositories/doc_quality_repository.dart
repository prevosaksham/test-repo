import 'package:dio/dio.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/network_info.dart';
import '../models/doc_quality_result.dart';
import '../services/doc_quality_service.dart';

/// Document image-quality use-case: connectivity check, Digio call, error
/// mapping, parse to [DocQualityResult].
class DocQualityRepository {
  DocQualityRepository({DocQualityService? service, NetworkInfo? networkInfo})
      : _service = service ?? DocQualityService(),
        _network = networkInfo ?? NetworkInfo();

  final DocQualityService _service;
  final NetworkInfo _network;

  /// Analyze an image. Returns the parsed result on success; throws
  /// [ApiException] on no-internet / API error / unreadable response (so the
  /// caller can distinguish a *technical* failure from a *quality* fail).
  Future<DocQualityResult> analyzeIdCard({
    required String filePath,
    required List<String> expectedIds,
    String? fileName,
  }) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      final json = await _service.analyzeIdCard(
        filePath: filePath,
        expectedIds: expectedIds,
        fileName: fileName,
      );
      final result = DocQualityResult.fromResponse(json);
      // Nothing parsed at all (neither quality checks nor a detection) → treat
      // as a technical failure the caller should retry, not a quality/type fail.
      if (!result.found && result.detectedIdType.isEmpty) {
        throw ApiException('Could not verify image quality. Please try again.');
      }
      return result;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Could not verify image quality. Please try again.');
    }
  }
}
