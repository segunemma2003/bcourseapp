import 'package:nylo_framework/nylo_framework.dart';

class PreloadEssentialDataEvent implements NyEvent {
  @override
  final listeners = {
    DefaultListener: DefaultListener(),
  };
}

class DefaultListener extends NyListener {
  @override
  handle(dynamic event) async {
    // Handle the event
  }
}
