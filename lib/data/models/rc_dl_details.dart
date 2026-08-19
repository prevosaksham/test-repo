/// RC Book + Driving License details fetched AFTER the RC upload + verify, from
/// `POST /field-verification/rc-dl-details` (body { applicationId }). The RC
/// block is read off the RC Book OCR; the DL block off the Driving License OCR
/// (null until a DL is uploaded/processed).
class RcDlDetails {
  const RcDlDetails({
    this.rc,
    this.dl,
    this.rcUrl = '',
    this.dlUrl = '',
    this.rcVerified = false,
  });

  final RcOcr? rc;
  final DlOcr? dl;
  // Uploaded file urls (rcBook.document.url / drivingLicense.document.url) —
  // used to view the uploaded RC Book / Driving License.
  final String rcUrl;
  final String dlUrl;
  // rcBook.verification.rcVerified — true once the RC has been verified (the
  // Verify button is disabled then).
  final bool rcVerified;

  factory RcDlDetails.fromResponse(Map<String, dynamic> json) {
    final data = json['data'];
    final map = data is Map ? Map<String, dynamic>.from(data) : const {};

    Map<String, dynamic>? ocrOf(String section) {
      final s = map[section];
      if (s is Map && s['ocr'] is Map) {
        return Map<String, dynamic>.from(s['ocr'] as Map);
      }
      return null;
    }

    String urlOf(String section) {
      final s = map[section];
      if (s is Map && s['document'] is Map) {
        final u = (s['document'] as Map)['url'];
        return u == null ? '' : u.toString();
      }
      return '';
    }

    bool verifiedOf(String section) {
      final s = map[section];
      if (s is Map && s['verification'] is Map) {
        return (s['verification'] as Map)['rcVerified'] == true;
      }
      return false;
    }

    final rcOcr = ocrOf('rcBook');
    final dlOcr = ocrOf('drivingLicense');
    return RcDlDetails(
      rc: rcOcr == null ? null : RcOcr.fromJson(rcOcr),
      dl: dlOcr == null ? null : DlOcr.fromJson(dlOcr),
      rcUrl: urlOf('rcBook'),
      dlUrl: urlOf('drivingLicense'),
      rcVerified: verifiedOf('rcBook'),
    );
  }
}

String _pick(Map<String, dynamic> j, List<String> keys) {
  for (final k in keys) {
    final v = j[k];
    if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
  }
  return '';
}

/// Vehicle (RC Book) OCR fields shown in the "Vehicle Details" block.
class RcOcr {
  const RcOcr({
    required this.registeredOwner,
    required this.registrationNumber,
    required this.registrationDate,
    required this.chassisNumber,
    required this.engineNumber,
    required this.manufacturer,
  });

  final String registeredOwner;
  final String registrationNumber;
  final String registrationDate;
  final String chassisNumber;
  final String engineNumber;
  final String manufacturer;

  factory RcOcr.fromJson(Map<String, dynamic> j) => RcOcr(
        registeredOwner: _pick(j, ['registeredOwner', 'ownerName', 'owner']),
        registrationNumber:
            _pick(j, ['registrationNumber', 'regNumber', 'rcNumber']),
        registrationDate: _pick(j, ['registrationDate', 'regDate']),
        chassisNumber: _pick(j, ['chassisNumber', 'chassisNo']),
        engineNumber: _pick(j, ['engineNumber', 'engineNo']),
        manufacturer: _pick(j, ['manufacturer', 'manufacturerName', 'makerName']),
      );
}

/// Driving License OCR fields shown in the "Driving License" block. Keys per the
/// `drivingLicense.ocr` payload: dlNumber, validityDate, dlIssueRTO.
class DlOcr {
  const DlOcr({
    required this.dlNumber,
    required this.expiryDate,
    required this.issuingRto,
  });

  final String dlNumber;
  final String expiryDate;
  final String issuingRto;

  factory DlOcr.fromJson(Map<String, dynamic> j) => DlOcr(
        dlNumber: _pick(j, ['dlNumber', 'licenseNumber', 'number']),
        expiryDate: _pick(j, ['validityDate', 'expiryDate', 'validUntil', 'dlExpiry']),
        issuingRto: _pick(j, ['dlIssueRTO', 'issuingRto', 'rtoName', 'issuingAuthority']),
      );
}
