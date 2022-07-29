// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter/material.dart';

// ignore: unused_import
import 'package:http/http.dart' as http;

class ApiRequest {
  String url;
  List<String> headers;
  List<String> data;
  String toMatch;
  String matched = "";
  List<String> result = [""];
  bool parseAsJson = true;
  ApiRequest({
    required this.url,
    required this.headers,
    required this.data,
    required this.toMatch,
    this.parseAsJson = true,
  }) {
    matched = "";
    result = [""];
  }
}

class ApiQuery {
  String name;
  List<ApiRequest> requests;
  ApiQuery({
    required this.name,
    required this.requests,
  });
}

class RunAPIBearer {
  String name;
  ApiRequest token;
  int refreshTokenAfterMinutes = 1 * 60 * 24;
  List<ApiQuery> queries = <ApiQuery>[];
  Map<String, String> variables = <String, String>{};
  RunAPIBearer({
    required this.name,
    required this.token,
    this.refreshTokenAfterMinutes = 1 * 60 * 24,
    this.queries = const <ApiQuery>[],
  });
}

class InterfaceApiSetup extends StatefulWidget {
  const InterfaceApiSetup({Key? key}) : super(key: key);

  @override
  InterfaceApiSetupState createState() => InterfaceApiSetupState();
}

class InterfaceApiSetupState extends State<InterfaceApiSetup> {
  List<RunAPIBearer> api = <RunAPIBearer>[
    RunAPIBearer(
        name: "Twitch",
        token: ApiRequest(
          url: "https://id.twitch.tv/oauth2/token",
          headers: <String>["Content-Type: application/x-www-form-urlencoded"],
          data: <String>["client_id=9duwo8nlogmbt6siqr6lkypxgyop05", "client_secret=1483rxcu10mddvkhkyrjsn42uooovx", "grant_type=client_credentials"],
          toMatch: "access_token",
        ),
        queries: <ApiQuery>[
          ApiQuery(name: "user info", requests: [
            ApiRequest(
              url: "https://api.twitch.tv/helix/users?login={params}",
              headers: <String>["Authorization: Bearer {bearer}", "Client-Id: {client-id}"],
              data: <String>[],
              toMatch: "",
            )
          ])
        ])
  ];
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text("Add New API"),
          onTap: () {},
        )
      ],
    );
  }
}
