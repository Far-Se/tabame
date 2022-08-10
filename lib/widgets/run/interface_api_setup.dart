// ignore_for_file: public_member_api_docs, sort_constructors_first
// ! Doesnt work, maybe I will come back in the future.
import 'dart:convert';

import 'package:flutter/material.dart';

// ignore: unused_import
import 'package:http/http.dart' as http;

import '../../models/classes/saved_maps.dart';
import '../../models/settings.dart';
import '../widgets/checkbox_widget.dart';
import '../widgets/popup_dialog.dart';
import '../widgets/text_input.dart';

class InterfaceApiSetup extends StatefulWidget {
  const InterfaceApiSetup({Key? key}) : super(key: key);

  @override
  InterfaceApiSetupState createState() => InterfaceApiSetupState();
}

class InterfaceApiSetupState extends State<InterfaceApiSetup> {
  List<RunAPI> savedAPI = <RunAPI>[
    RunAPI(
      name: "Twitch",
      token: ApiRequest(
        url: "https://id.twitch.tv/oauth2/token",
        headers: <String>["Content-Type: application/x-www-form-urlencoded"],
        data: <String>["client_id={client_id}", "client_secret={client_secret}", "grant_type=client_credentials"],
        toMatch: "access_token",
      ),
      queries: <ApiQuery>[
        ApiQuery(
          name: "user info",
          requests: <ApiRequest>[
            ApiRequest(
              url: "https://api.twitch.tv/helix/streams",
              headers: <String>["Authorization: Bearer {token}", "Client-Id: {client_id}"],
              data: <String>[],
              toMatch: "",
            )
          ],
        ),
      ],
      variables: <String, String>{"client_id": "9duwo8nlogmbt6si6lkypxgyop05", "client_secret": "1483rxcu10mddvkhkyrjsnuooovx", "token": "9mftqbpdbesyral7otvmjljb10i2"},
    )
  ];

  List<int> expandedApis = <int>[0];

  List<TextEditingController> variableController = <TextEditingController>[];
  @override
  void initState() {
    for (RunAPI i in savedAPI) {
      String text = "";
      for (MapEntry<String, String> x in i.variables.entries) {
        text += "${x.key}=${x.value}\n";
      }
      variableController.add(TextEditingController(text: text));
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text("Add New API"),
          onTap: () {
            savedAPI.add(RunAPI(name: "new Api"));
            variableController.add(TextEditingController());
            setState(() {});
          },
        ),
        ListView.builder(
          shrinkWrap: true,
          itemCount: savedAPI.length,
          controller: ScrollController(),
          itemBuilder: (BuildContext context, int index) {
            final RunAPI api = savedAPI[index];

            return Column(
              children: <Widget>[
                ListTile(
                  title: Text(api.name),
                  leading: !expandedApis.contains(index) ? Icon(Icons.expand_more, color: Colors.grey.shade700) : const Icon(Icons.expand_less),
                  onTap: () => setState(() => expandedApis.toggle(index)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () {
                      savedAPI.removeAt(index);
                      variableController.removeAt(index);
                      setState(() {});
                      //!save
                    },
                  ),
                ),
                if (expandedApis.contains(index))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                                child: Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: Column(
                                        children: <Widget>[
                                          TextInput(key: UniqueKey(), value: api.name, labelText: "Api Name", onChanged: (String val) => setState(() => api.name = val)),
                                          CheckBoxWidget(
                                              onChanged: (bool val) => setState(() => api.refreshTokenAfterMinutes = val == true ? 2 * 60 * 24 : 0),
                                              value: api.refreshTokenAfterMinutes > 0,
                                              text: "Uses Bearer Token"),
                                          if (api.refreshTokenAfterMinutes > 0)
                                            TextField(
                                              keyboardType: TextInputType.multiline,
                                              maxLines: null,
                                              controller: TextEditingController(text: api.refreshTokenAfterMinutes.toString()),
                                              decoration:
                                                  const InputDecoration(labelText: "Token Expiration in minutes(press Enter)", isDense: true, border: InputBorder.none),
                                              onSubmitted: (String v) => setState(() => api.refreshTokenAfterMinutes = int.parse(v)),
                                              toolbarOptions: const ToolbarOptions(copy: true, cut: true, paste: true, selectAll: true),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        children: <Widget>[
                                          Focus(
                                            onFocusChange: (bool f) => !f
                                                ? setState(() {
                                                    // api.va = variableController[index].text.split("\n");
                                                    final List<String> textLines = variableController[index].text.split("\n");
                                                    final Map<String, String> newMap = <String, String>{};
                                                    for (String text in textLines) {
                                                      final List<String> keyval = text.split("=");
                                                      if (keyval.length != 2) continue;
                                                      newMap[keyval[0]] = keyval[1];
                                                    }
                                                    api.variables = newMap;
                                                  })
                                                : true,
                                            child: TextField(
                                              keyboardType: TextInputType.multiline,
                                              maxLines: null,
                                              decoration: const InputDecoration(labelText: "Variables:", isDense: true, border: InputBorder.none),
                                              controller: variableController[index],
                                              toolbarOptions: const ToolbarOptions(copy: true, cut: true, paste: true, selectAll: true),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (api.refreshTokenAfterMinutes > 0) ModifyApiInfo(api: api.token, isToken: true, variables: api.variables),
                                ...List<Widget>.generate(api.queries.length, (int index) {
                                  return Column(
                                    children: <Widget>[
                                      ListTile(title: Text(api.queries[index].name)),
                                      for (ApiRequest x in api.queries[index].requests) ModifyApiInfo(api: x, variables: api.variables),
                                    ],
                                  );
                                })
                              ],
                            )),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        )
      ],
    );
  }
}

class ModifyApiInfo extends StatefulWidget {
  final ApiRequest api;
  final bool isToken;
  final Map<String, String> variables;
  const ModifyApiInfo({Key? key, required this.api, this.isToken = false, required this.variables}) : super(key: key);

  @override
  ModifyApiInfoState createState() => ModifyApiInfoState();
}

class ModifyApiInfoState extends State<ModifyApiInfo> {
  final TextEditingController headersController = TextEditingController();
  final TextEditingController dataController = TextEditingController();

  final TextEditingController matchController = TextEditingController();
  @override
  void initState() {
    headersController.text = widget.api.headers.join("\n");
    dataController.text = widget.api.data.join("\n");
    matchController.text = widget.api.toMatch;
    super.initState();
  }

  @override
  void dispose() {
    headersController.dispose();
    dataController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextInput(value: widget.api.url, labelText: "Link", onChanged: (String val) => setState(() => widget.api.url = val)),
              const Text("Headers:"),
              Focus(
                onFocusChange: (bool f) => !f ? setState(() => widget.api.headers = headersController.text.split("\n")) : true,
                child: TextField(
                  keyboardType: TextInputType.multiline,
                  maxLines: null,
                  decoration: const InputDecoration(labelText: "Headers, multiline", isDense: true, border: InputBorder.none),
                  controller: headersController,
                  toolbarOptions: const ToolbarOptions(copy: true, cut: true, paste: true, selectAll: true),
                ),
              ),
              const Text("Data:"),
              Focus(
                onFocusChange: (bool f) => !f ? setState(() => widget.api.data = dataController.text.split("\n")) : true,
                child: TextField(
                  keyboardType: TextInputType.multiline,
                  maxLines: null,
                  decoration: const InputDecoration(labelText: "Data, multiline", isDense: true, border: InputBorder.none),
                  controller: dataController,
                  toolbarOptions: const ToolbarOptions(copy: true, cut: true, paste: true, selectAll: true),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CheckBoxWidget(onChanged: (bool checked) => setState(() => widget.api.parseAsJson = checked), value: widget.api.parseAsJson, text: "Parse as Json"),
              if (widget.api.parseAsJson) const Text("To match sub tree items, use ->. To match  multiple items, use [item,item]"),
              if (widget.api.parseAsJson)
                const Text("Example: body->results->[]->[views,revenue]")
              else
                const Text("To match multiple, use (?!a|b|c), EX: (?!item1|item2)=(.*?)\\n"),
              const Text("Match:"),
              Focus(
                onFocusChange: (bool f) => !f ? setState(() => widget.api.data = dataController.text.split("\n")) : true,
                child: TextField(
                  keyboardType: TextInputType.multiline,
                  maxLines: null,
                  decoration: InputDecoration(labelText: "Match ${widget.api.parseAsJson ? "" : "(regex aware)"}", isDense: true, border: InputBorder.none),
                  controller: matchController,
                  toolbarOptions: const ToolbarOptions(copy: true, cut: true, paste: true, selectAll: true),
                ),
              ),
              ElevatedButton(
                child: Text("Test", style: TextStyle(color: Theme.of(context).backgroundColor)),
                onPressed: () {
                  final Map<String, String> headers = <String, String>{};
                  String data = widget.api.data.join("&");

                  for (MapEntry<String, String> map in widget.variables.entries) {
                    if (map.key.isEmpty) continue;
                    data = data.replaceAll("{${map.key}}", map.value);
                  }

                  for (String header in widget.api.headers) {
                    final List<String> keyval = header.split(':');
                    if (keyval.length != 2) continue;
                    String val = keyval[1].trim();
                    for (MapEntry<String, String> map in widget.variables.entries) {
                      val = val.replaceAll("{${map.key}}", map.value);
                    }
                    headers[keyval[0]] = val;
                  }

                  http
                      .post(
                    Uri.parse(widget.api.url),
                    headers: headers,
                    body: data,
                  )
                      .then((http.Response response) {
                    if (response.statusCode != 200) {
                      popupDialog(context, "Status code not 200, but ${response.statusCode}");
                      return;
                    }
                    if (widget.api.parseAsJson) {
                      final Map<String, dynamic> json = jsonDecode(response.body);
                      if (json.containsKey(widget.api.toMatch)) {
                        widget.api.matched = <String>[json[widget.api.toMatch]];
                      }
                      widget.api.result = response.body;
                      if (mounted) setState(() {});
                    }
                    return null;
                  }).catchError((dynamic onError) {
                    if (mounted) popupDialog(context, "Fetch failed $onError");
                  });
                },
              ),
              TextInput(key: UniqueKey(), value: widget.api.matched.join("\n"), labelText: "Matched", onChanged: (String e) {}),
              TextInput(multiline: true, key: UniqueKey(), value: widget.api.result, labelText: "Response", onChanged: (String e) {}),
            ],
          ),
        )
      ],
    );
  }
}
