class EnrollmentData {
  static List<Map<String, dynamic>> getEnrollmentPlans() {
    return [
      {
        'title': 'Bhavani',
        'badge': 'PRO',
        'price': '₹1,500.00',
        'duration': '1 year',
        'features': [
          'unlimited access to over 50+ hands-on courses with free certification',
          'High Quality 1080P training video content',
          'All training videos available to be downloaded offline during enrollment period',
        ],
      },
      {
        'title': 'Course Basic Plan',
        'badge': '',
        'price': '₹1,500.00',
        'duration': '2 months',
        'features': [
          'unlimited access to this hands-on course with free certification',
          'High Quality 480P training video content',
          'This course\'s training videos available to be downloaded offline during enrollment period',
        ],
      },
      {
        'title': 'Course Scholar Plan',
        'badge': '',
        'price': '₹1,500.00',
        'duration': '6 months',
        'features': [
          'unlimited access to this hands-on course with free certification',
          'High Quality 720P training video content',
          'This course\'s training videos available to be downloaded offline during enrollment period',
        ],
      },
    ];
  }
}
