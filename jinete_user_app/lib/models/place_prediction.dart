class PlacePrediction {
  String? placeId;
  String? mainText;
  String? secondaryText;

  PlacePrediction({this.placeId, this.mainText, this.secondaryText});

  PlacePrediction.fromJson(Map<String, dynamic> json) {
    placeId = json["placePrediction"]["placeId"];
    mainText = json["placePrediction"]["structuredFormat"]["mainText"]["text"];
    secondaryText =
        json["placePrediction"]["structuredFormat"]["secondaryText"]["text"];
  }
}
