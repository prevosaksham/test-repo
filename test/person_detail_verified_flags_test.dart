import 'package:flutter_test/flutter_test.dart';
import 'package:erikshaapp/data/models/person_detail.dart';

void main() {
  group('PersonDetail server verification flags', () {
    test('pan_verified / aadhar_verified true → flags set', () {
      final p = PersonDetail.fromJson(const {
        'id': '208',
        'fullName': 'KIRAN MAHESH BAJIRAO',
        'panNumber': 'ELKPB8502H',
        'pan_verified': true,
        'aadhar_verified': true,
      });
      expect(p.panVerified, isTrue);
      expect(p.aadhaarVerified, isTrue);
    });

    test('false / missing → flags stay false', () {
      final p = PersonDetail.fromJson(const {
        'fullName': 'X',
        'pan_verified': false,
      });
      expect(p.panVerified, isFalse);
      expect(p.aadhaarVerified, isFalse);
    });

    test('tolerates 1 / "true" and camelCase keys', () {
      final a = PersonDetail.fromJson(const {'pan_verified': 1});
      final b = PersonDetail.fromJson(const {'aadhar_verified': 'true'});
      final c = PersonDetail.fromJson(const {'panVerified': true});
      expect(a.panVerified, isTrue);
      expect(b.aadhaarVerified, isTrue);
      expect(c.panVerified, isTrue);
    });

    test('parses off the real /application/details shape', () {
      final d = ApplicationDetails.fromResponse(const {
        'data': {
          'application': {'id': '317'},
          'applicant': {
            'id': '208',
            'pan_verified': true,
            'aadhar_verified': true,
          },
          'coApplicants': {
            'id': '206',
            'pan_verified': true,
            'aadhar_verified': true,
          },
        },
      });
      expect(d.applicant!.panVerified, isTrue);
      expect(d.applicant!.aadhaarVerified, isTrue);
      expect(d.coApplicant!.panVerified, isTrue);
      expect(d.coApplicant!.aadhaarVerified, isTrue);
    });
  });
}
