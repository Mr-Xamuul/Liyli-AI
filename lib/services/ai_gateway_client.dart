import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// Calls the authenticated Supabase Edge Function without exposing provider
/// credentials to Flutter clients.
class AiGatewayClient {
  const AiGatewayClient();

  Future<http.Response> generate({
    required String modelId,
    required String operation,
    required Map<String, dynamic> body,
  }) async {
    final result = await SupabaseConfig.client.functions.invoke(
      'ai-gateway',
      body: {
        'action': 'proxy',
        'modelId': modelId,
        'operation': operation,
        'body': body,
      },
    );
    final data = result.data;
    if (data is! Map<String, dynamic>) {
      return http.Response(
        jsonEncode({
          'error': {'message': 'AI gateway jawaab sax ah ma soo celin.'},
        }),
        502,
      );
    }
    final status = (data['providerStatus'] as num?)?.toInt() ?? 502;
    final responseBody = data['providerBody']?.toString() ?? '';
    return http.Response(
      responseBody,
      status,
      headers: const {'content-type': 'application/json'},
    );
  }

  Future<({bool success, String message})> verifyModel({
    required String modelId,
    required String provider,
    required String baseUrl,
    required String apiKeyId,
    required bool isTts,
  }) async {
    try {
      final result = await SupabaseConfig.client.functions.invoke(
        'ai-gateway',
        body: {
          'action': 'verify_model',
          'modelId': modelId,
          'provider': provider,
          'baseUrl': baseUrl,
          'apiKeyId': apiKeyId,
          'isTts': isTts,
        },
      );
      final data = result.data as Map<String, dynamic>;
      return (
        success: data['success'] == true,
        message:
            data['message']?.toString() ??
            'Xaqiijinta model-ka way fashilantay.',
      );
    } on FunctionException catch (error) {
      return (
        success: false,
        message:
            error.details?.toString() ??
            'Xaqiijinta server-ka way fashilantay.',
      );
    } catch (error) {
      return (
        success: false,
        message: 'Xaqiijinta server-ka way fashilantay: $error',
      );
    }
  }
}
