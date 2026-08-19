/// Central place for the base URL and API paths.
class ApiEndpoints {
  ApiEndpoints._();

  //static const String baseUrl = 'http://35.207.195.114:3000/backend/api';
  //static const String baseUrl = 'http://35.200.198.14:3000/backend/api';
  static const String baseUrl = 'https://nbfc.prevoyancesolutions.com/backend/api';

  // Auth
  static const String login = '/auth/login';
  static const String verifyOtp = '/auth/verify-otp';
  static const String forgotPassword = '/auth/forgot-password';
  static const String resendForgotOtp = '/auth/resend-forgot-otp';
  static const String verifyForgotOtp = '/auth/verify-forgot-otp';
  static const String resetPassword = '/auth/reset-password';

  // Dashboard (Home)
  static const String rmDashboard = '/rm/dashboard';
  static const String followupList = '/followup/list';
  // Follow-up history (More → View All). POST { page_limit, page_number,
  // search, date } — server-paginated with search + date filter.
  static const String followupHistory = '/followup/history';



  // Leads
  static const String rmList = '/rm/list';
  static const String rmGetPreview = '/rm/getPreview';
  // Read-only Application/Lead details for the My Leads → "View" screen.
  // POST { leadId } → data: { lead, application, timeline[], applicationDetails }.
  static const String rmLeadDetails = '/rm/lead-details';
  // Eye-icon "Lead Details" popup — POST { leadId } → data: { basicDetails,
  // vehicleDetails }.
  static const String rmLeadBasicDetails = '/rm/lead-basic-details';
  static const String rmScheduleCall = '/rm/scheduleCall';
  static const String rmGetDealers = '/rm/getDealers';
  static const String rmScheduleVisit = '/rm/scheduleVisit';
  // Completes the Start-Application lead stage (leadId + callId + visitId),
  // unlocking the application stages. Caller re-fetches getPreview after.
  static const String rmCompleteStartApplication = '/rm/lead/preview';

  // Financial / Loan Approval — POST { applicationId } → approved loan summary +
  // generated documents (Sanction Letter / Loan Agreement / KFS / Repayment).
  static const String rmFinancialApproval = '/field-verification/details';

  // Field Investigation submit — POST { applicationId, latitude, longitude,
  // geoAddress, addressMatchStatus, status, remarks, reason, verificationDate }.
  static const String fieldVerificationCreate = '/field-verification/create';

  static const String predisbursal = '/field-verification/pre-disbursal/submit';
  // Post-Disbursal submit — POST { applicationId, stageId }.
  static const String postDisbursementSubmit =
      '/application/post-disbursement/submit';

  //api/field-verification/details

  // Generated-document PDF — POST { applicationId, documentType }.
  // preview → view the PDF in-app; download → save the PDF to the device.
  static const String pdfPreview = '/pdf/preview';
  static const String pdfDownload = '/pdf/download';

  // Reports
  static const String getMonthlyLeadTrend = '/rm/getMonthlyLeadTrend';

  // Lead status list for the My Leads filter. GET → data: [{value, display_name}].
  static const String rmStatus = '/rm/rm-status';

  // Privacy Policy. POST { language: 'en'|'hi'|'mr' } → data: { title,
  // sections: [{ id, title, content }] }.
  static const String privacyPolicy = '/privacy-policy';

  // Terms & Conditions. POST { language: 'en'|'hi'|'mr' } → data: { title,
  // sections: [{ id, title, content }] }.
  static const String privacyPolicyTerms = '/privacy-policy/terms';

  // Profile (My Profile screen). GET.
  static const String rmGetProfile = '/rm/get-profile';
  // Edit Profile — GET prefill (editable fields) + PUT to save the edits
  // (body: fullName, mobile, dateOfBirth).
  static const String rmEditProfile = '/rm/edit-profile';

  // Application — multipart upload of KYC documents (Upload Document stage).
  // NOTE: the dev curl is `localhost:3000/api/application/upload-documents`;
  // this resolves against [baseUrl]. Adjust if this service has a different host.
  static const String applicationUploadDocuments = '/application/upload-documents';

  // Application — per-document upload (one document, or one front+back pair, at a
  // time). Sends ONLY the file field(s) + leadId. The rest of the application
  // data goes on the (separate) Proceed API. Resolves against [baseUrl].
  static const String applicationUpload = '/application/upload';

  // Loan application — server-side RC verification, fired after the RC Book is
  // uploaded on the Post-Disbursal screen. POST { applicationId }.
  // NOTE: dev curl is `localhost:3000/api/loan-application/verify`; resolves
  // against [baseUrl].
  static const String loanApplicationVerify = '/loan-application/verify';

  // Field verification — RC Book + Driving License OCR details, fetched after
  // the RC upload + verify on the Post-Disbursal screen. POST { applicationId }.
  static const String fieldVerificationRcDlDetails =
      '/field-verification/rc-dl-details';

  // Application — full details (incl. already-uploaded applicant/co-applicant
  // documents with base64 dataUri previews). POST { leadId }. Used to re-show the
  // user's previously uploaded images when they return to the Upload screen.
  static const String applicationDetails = '/application/details';
  // Disbursement Status page — POST { leadId } → data: { title, subtitle,
  // isDisbursed, disbursementSummary, loanAccountActivated, canProceedToPostDisbursal }.
  static const String applicationDisbursementStatus =
      '/application/disbursement-status';

  // Application — delete an uploaded document. POST { leadId, docCode } where
  // docCode is the grouped document code (AADHAAR, CO_PAN, PASSBOOK, …).
  static const String applicationDeleteDocument = '/application/delete-document';

  // Application — fetch ONE uploaded document's full file on demand. POST
  // { documentId, applicantType } (applicantType = APPLICANT / CO_APPLICANT) →
  // data.fileData.dataUri (base64). The /application/details list now carries
  // only a small `thumbnail`, so the full image/PDF is loaded here when viewed.
  static const String applicationDocument = '/application/document';

  // Consent — list of consent/terms items shown on the Applicant/Co-Applicant
  // Consent screen. POST { lang: 'en'|'hi'|'mr' } → data: [{ displayName,
  // content, order, isMandatory }] in the chosen language.
  static const String consentList = '/consent/list';

  // Consent — send OTP to the applicant + co-applicant for consent capture
  // (OTP mode). POST { applicationId, consentIds:[int],
  // applicantTypes:[{ applicantType, mobileNumber }] }.
  static const String consentSendOtp = '/consent/send-otp';

  // Consent — send the consent LINK to the applicant + co-applicant (Link mode).
  // Same body shape as send-otp.
  static const String consentSendLink = '/consent/send-link';

  // Consent — resend OTP to a SINGLE applicant type (APPLICANT / CO_APPLICANT).
  // POST { applicationId, consentIds:[int], applicantType }.
  static const String consentResendOtp = '/consent/resend-otp';

  // Consent — resend the LINK to a SINGLE applicant type (APPLICANT /
  // CO_APPLICANT). POST { applicationId, consentIds:[int], applicantType }.
  static const String consentResendLink = '/consent/resend-link';
  // Consent — poll acceptance status (Link mode). POST { applicationId } →
  // data.isConsentAccepted. When true, move to the Consent Captured screen.
  static const String consentStatus = '/consent/status';

  // Consent — verify the OTP for a SINGLE applicant type.
  // POST { applicationId, applicantType, otp }. 
  static const String consentVerifyOtp = '/consent/verify-otp';

  // Application — save applicant + co-applicant details (Application Details
  // step Proceed). POST { appData, coAppData, stageId, stageType, status,
  // leadId }. appData/coAppData are the full person objects from /details.
  static const String applicationSaveApplicant = '/application/save-applicant';

  // Application — save the consent terms (on the OTP Verified screen's Proceed).
  // POST { applicationId, leadId, stageId, stageType, consentIds:[int] }.
  static const String applicationSaveTerm = '/application/save-term';

  // Application — save KYC document verification (on the KYC screen's Proceed).
  // POST { applicationId, leadId, stageId, stageType,
  // docsVerifications:[{ applicantType, documentCode }] }.
  static const String applicationSaveVerification =
      '/application/save-verification';

  // Application — final submit (on the Submit Application screen).
  // POST { applicationId, leadId, stageId, stageType, status }.
  static const String applicationSubmit = '/application/submit';

  // Application — initiate Aadhaar-linked eSign for all documents (eSign Pending
  // screen's "Initiate eSign" button). POST { applicationId }. NOTE: the dev
  // curl is `localhost:3000/api/application/esign/initiate-multi`; this resolves
  // against [baseUrl].
  static const String applicationEsignInitiateMulti =
      '/application/esign/initiate-multi';

  // Loan application — save the Disbursement Validation answers (eSign Success
  // screen's Proceed). POST { applicationId, questions:[{ key, answer:bool }] }.
  static const String loanApplicationQuestions = '/loan-application/questions';

  // Application — complete a MANUAL e-sign (eSign Pending screen's Proceed after
  // the signed documents are uploaded). POST { applicationId, stageId }.
  static const String applicationEsignManual = '/application/esign/manual';

  // Bank — bank account verification on the KYC screen's per-passbook Verify.
  // POST { id_number, ifsc, ifsc_details:true } where id_number is the
  // applicant's bank account number and ifsc is the IFSC code (both taken from
  // /application/details `bankDetails`). NOTE: the dev curl is
  // `localhost:3000/api/bank-verification`; this resolves against [baseUrl].
  static const String bankVerification = '/bank-verification';

  // Application — PAN verification on the KYC screen's per-PAN Verify.
  // POST { application_id, applicantType, id_number, full_name, dob } where
  // id_number is that person's PAN and dob is yyyy-MM-dd (both from
  // /application/details).
  static const String panVerification = '/application/pan-verification';

  // Application — Aadhaar verification on the KYC screen's per-Aadhaar Verify.
  // POST { application_id, applicantType, id_number } where id_number is that
  // person's Aadhaar number (from /application/details).
  static const String aadhaarVerification =
      '/application/aadhaar-verification';

  // Location — house-ownership checksum used to derive the Residence Type on the
  // Application Details screen. POST { applicant: { fullName, fatherName,
  // maritalStatus, permanentAddressProofName }, coApplicant: { fullName,
  // relationshipStatus, permanentAddressProofName } } where
  // permanentAddressProofName is that person's Owner Name (consumerName).
  // → data: { applicant: { ownership, … }, coApplicant: { ownership, … } }.
  static const String locationChecksum = '/location/checksum';




}

/// Default role sent with auth requests for this RM build.
class AppConstants {
  AppConstants._();
  static const String defaultRole = 'sales_agent';
}
