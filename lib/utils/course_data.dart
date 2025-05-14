import '../app/models/course.dart';

class CourseData {
  static List<Course> getFeaturedCourses() {
    return [];
  }

  static List<Map<String, dynamic>> getCurriculumItems() {
    return [
      {
        'id': 1,
        'title': 'Class Introduction Video',
        'duration': '13m',
      },
      {
        'id': 2,
        'title': 'Class Introduction Video',
        'duration': '15m',
      },
      {
        'id': 3,
        'title': 'Class Introduction Video',
        'duration': '10m',
      },
      {
        'id': 4,
        'title': 'Class Introduction Video',
        'duration': '12m',
      },
      {
        'id': 5,
        'title': 'Class Introduction Video',
        'duration': '8m',
      },
    ];
  }

  static List<String> getAchievements() {
    return [
      'Learn how to create a strong brand identity that stands out in the fashion market. From naming to visuals, you\'ll craft a boutique that truly reflects your vision.',
      'Discover the best ways to find reliable suppliers and high-quality items for your store.',
      'Master social media, influencer partnerships, and other modern tools to draw attention to your boutique.',
      'Receive a professional certificate once you finish the course. It\'s a great way to showcase your skills and boost credibility as a boutique owner.',
    ];
  }

  static List<String> getRequirements() {
    return [
      'You\'ll need a basic sewing machine along with essential tailoring tools like measuring tape, scissors, threads, and fabric. These materials will help you practice hands-on techniques and bring your boutique designs to life.',
      'Having a small, dedicated space, even a corner of your room will help you stay organized and focused. It\'s where you\'ll be sketching ideas, sewing, and managing your mini studio as you build your boutique.',
    ];
  }

  static Future<Course> fetchCourseDetail(String courseId) async {
    // Simulate API call
    // await Future.delayed(Duration(seconds: 1));

    // Find the course with the matching ID
    List<Course> allCourses = getFeaturedCourses();
    Course? course = allCourses.firstWhere(
      (course) => course.id == courseId,
      orElse: () => allCourses[0], // Default to first course if not found
    );

    return course;
  }
}
