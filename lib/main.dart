import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:device_apps/device_apps.dart';
import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shareapp/SplashScreen.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Share App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: SplashPage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
    with SingleTickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isLoading = false;
  StreamController<bool> _streamController = StreamController<bool>();

  TabController _tabController;
  // List<ApplicationWithIcon> _applications = [];
  // List<FileSystemEntity> _videoFiles = [];
  // List<FileSystemEntity> _musicFiles = [];
  // List<FileSystemEntity> _imageFiles = [];

  List<CustomFile> _selectedFiles = [];
  List<CustomFile> _sendFiles = [];
  bool _selectedMode = false;
  bool _appMode = false;
  bool _videosMode = false;
  bool _musicMode = false;
  bool _imageMode = false;
  bool _sending = false;

  final nearby = Nearby();
  final String userName = Random().nextInt(10000).toString();
  final Strategy strategy = Strategy.P2P_STAR;

  String cId = "0"; //currently connected device ID
  File tempFile; //reference to the file currently being transferred
  Map<int, String> map =
      Map(); //store filename mapped to corresponding payloadId

  OverlayEntry _overlayEntry;
  OverlayState _overlayState;
  // Map<String, String> _deviceMap = {};

  _init() async {
    await _fetchApps();
  }

  void showSnackbar(dynamic a) {
    _scaffoldKey.currentState.showSnackBar(SnackBar(
      content: Text(a.toString()),
    ));
  }

//   /// Called upon Connection request (on both devices)
//   /// Both need to accept connection to start sending/receiving
  void onConnectionInit(String id, ConnectionInfo info) {
    showModalBottomSheet(
      context: context,
      builder: (builder) {
        return Center(
          child: Column(
            children: <Widget>[
              Text("id: " + id),
              Text("Token: " + info.authenticationToken),
              Text("Name" + info.endpointName),
              Text("Incoming: " + info.isIncomingConnection.toString()),
              RaisedButton(
                child: Text("Accept Connection"),
                onPressed: () {
                  Navigator.pop(context);
                  cId = id;
                  nearby.acceptConnection(
                    id,
                    onPayLoadRecieved: (endid, payload) async {
                      _streamController.sink.add(true);
                      if (payload.type == PayloadType.BYTES) {
                        String str = String.fromCharCodes(payload.bytes);
                        showSnackbar(endid + ": " + str);

                        if (str.contains(':')) {
                          // used for file payload as file payload is mapped as
                          // payloadId:filename
                          int payloadId = int.parse(str.split(':')[0]);
                          String fileName = (str.split(':')[1]);

                          if (map.containsKey(payloadId)) {
                            if (await tempFile.exists()) {
                              tempFile.rename(
                                  tempFile.parent.path + "/" + fileName);
                            } else {
                              showSnackbar("File doesnt exist");
                            }
                          } else {
                            //add to map if not already
                            map[payloadId] = fileName;
                          }
                        }
                      } else if (payload.type == PayloadType.FILE) {
                        showSnackbar(endid + ": File transfer started");
                        tempFile = File(payload.filePath);
                      }
                    },
                    onPayloadTransferUpdate: (endid, payloadTransferUpdate) {
                      if (payloadTransferUpdate.status ==
                          PayloadStatus.IN_PROGRRESS) {
                        print(payloadTransferUpdate.bytesTransferred);
                      } else if (payloadTransferUpdate.status ==
                          PayloadStatus.FAILURE) {
                        print("failed");
                        showSnackbar(endid + ": FAILED to transfer file");
                        _streamController.sink.add(false);
                      } else if (payloadTransferUpdate.status ==
                          PayloadStatus.SUCCESS) {
                        showSnackbar(
                            "success, total bytes = ${payloadTransferUpdate.totalBytes}");

                        if (map.containsKey(payloadTransferUpdate.id)) {
                          //rename the file now
                          // String name = map[payloadTransferUpdate.id];
                          // tempFile.rename(tempFile.parent.path + "/" + name);
                        } else {
                          //bytes not received till yet
                          map[payloadTransferUpdate.id] = "";
                        }
                        tempFile.copy(
                            '/storage/emulated/0/${tempFile.path.split('/').last}');
                        _streamController.sink.add(false);
                      }
                    },
                  );
                },
              ),
              RaisedButton(
                child: Text("Reject Connection"),
                onPressed: () async {
                  Navigator.pop(context);
                  try {
                    await Nearby().rejectConnection(id);
                  } catch (e) {
                    showSnackbar(e);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  _askPermissions() async {
    try {
      if (!await nearby.checkLocationEnabled()) {
        nearby.enableLocationServices();
      }

      if (!await nearby.checkLocationPermission()) {
        // asks for permission only if its not given
        nearby.askLocationPermission();
      }

      // OPTIONAL: if you need to transfer files and rename it on device
      if (!await nearby.checkExternalStoragePermission()) {
        // asks for READ + WRTIE EXTERNAL STORAGE permission only if its not given
        nearby.askExternalStoragePermission();
      }
    } catch (e) {
      _scaffoldKey.currentState
          .showSnackBar(SnackBar(content: Text("Exception: ${e.toString()}")));
    }
  }

  _advertiseConnection() async {
    try {
      bool a = await nearby.startAdvertising(
        userName,
        Strategy.P2P_STAR,
        onConnectionInitiated: (String id, ConnectionInfo info) {
          // Called whenever a discoverer requests connection
          // accept here and close discovery
          // _acceptForConnection(id);
          onConnectionInit(id, info);
        },
        onConnectionResult: (String id, Status status) {
          // Called when connection is accepted/rejected
        },
        onDisconnected: (String id) {
          // Callled whenever a discoverer disconnects from advertiser
        },
        serviceId: "com.yourdomain.appname", // uniquely identifies your app
      );
      _scaffoldKey.currentState
          .showSnackBar(SnackBar(content: Text("Advertise: ${a.toString()}")));
    } catch (e) {
      // platform exceptions like unable to start bluetooth or insufficient permissions
      _scaffoldKey.currentState
          .showSnackBar(SnackBar(content: Text("Exception: ${e.toString()}")));
    }
  }

  _discoverConnection() async {
    try {
      bool a = await nearby.startDiscovery(
        userName,
        Strategy.P2P_STAR,
        onEndpointFound: (String id, String userName, String serviceId) {
          // called when an advertiser is found
          // request a connection and close discovery
          // _requestForConnection(userName, id);
          // _deviceMap[id] = userName;
          // setState(() {});
          showModalBottomSheet(
            context: context,
            builder: (builder) {
              return Center(
                child: Column(
                  children: <Widget>[
                    Text("id: " + id),
                    Text("Name: " + userName),
                    Text("ServiceId: " + serviceId),
                    RaisedButton(
                      child: Text("Request Connection"),
                      onPressed: () {
                        Navigator.pop(context);
                        Nearby().requestConnection(
                          userName,
                          id,
                          onConnectionInitiated: (id, info) {
                            onConnectionInit(id, info);
                          },
                          onConnectionResult: (id, status) {
                            showSnackbar(status);
                          },
                          onDisconnected: (id) {
                            showSnackbar(id);
                          },
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
        onEndpointLost: (String id) {
          //called when an advertiser is lost (only if we weren't connected to it )
        },
        serviceId: "com.yourdomain.appname", // uniquely identifies your app
      );
      _scaffoldKey.currentState
          .showSnackBar(SnackBar(content: Text("Discover: ${a.toString()}")));
    } catch (e) {
      // platform exceptions like unable to start bluetooth or insufficient permissions
      _scaffoldKey.currentState
          .showSnackBar(SnackBar(content: Text("Exception: ${e.toString()}")));
    }
  }

  _requestForConnection(String username, String id) async {
    try {
      nearby.requestConnection(
        username,
        id,
        onConnectionInitiated: (id, info) {
          onConnectionInit(id, info);
        },
        onConnectionResult: (id, status) {},
        onDisconnected: (id) {},
      );
    } catch (e) {
      // called if request was invalid
      _scaffoldKey.currentState
          .showSnackBar(SnackBar(content: Text("Exception: ${e.toString()}")));
    }
  }

  _fetchApps() async {
    if (!_appMode) {
      setState(() {
        _isLoading = true;
      });

      if (!await Permission.storage.request().isGranted) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      try {
        var apps =
            await DeviceApps.getInstalledApplications(includeAppIcons: true);

        for (var ap in apps) {
          // _applications.add(ap as ApplicationWithIcon);
          _selectedFiles.add(CustomFile(
              applicationWithIcon: ap as ApplicationWithIcon,
              isSelected: false,
              type: FileType.APK));
        }
        setState(() {
          _isLoading = false;
          _appMode = true;
        });
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        print(e);
      }
    }
  }

  _fetchVideos() async {
    if (!_videosMode) {
      setState(() {
        _isLoading = true;
      });

      if (!await Permission.storage.request().isGranted) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final _dir = Directory('/storage/emulated/0/');
      print(_dir.path);

      try {
        List<FileSystemEntity> _files;
        _files = _dir.listSync(recursive: true, followLinks: false);
        for (FileSystemEntity entity in _files) {
          String path = entity.path;
          if (path.endsWith('.mp4'))
            _selectedFiles.add(CustomFile(
                file: entity, isSelected: false, type: FileType.VIDEO));
        }

        setState(() {
          _isLoading = false;
          _videosMode = true;
        });
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        print(e);
      }
    }
  }

  _fetchMusic() async {
    if (!_musicMode) {
      setState(() {
        _isLoading = true;
      });

      if (!await Permission.storage.request().isGranted) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final _dir = Directory('/storage/emulated/0/');
      print(_dir.path);

      try {
        List<FileSystemEntity> _files;
        _files = _dir.listSync(recursive: true, followLinks: false);
        for (FileSystemEntity entity in _files) {
          String path = entity.path;
          if (path.endsWith('.mp3'))
            _selectedFiles.add(CustomFile(
                file: entity, type: FileType.MUSIC, isSelected: false));
        }

        setState(() {
          _isLoading = false;
          _musicMode = true;
        });
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        print(e);
      }
    }
  }

  _fetchImages() async {
    if (!_imageMode) {
      setState(() {
        _isLoading = true;
      });

      if (!await Permission.storage.request().isGranted) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final _dir = Directory('/storage/emulated/0/');
      print(_dir.path);

      try {
        List<FileSystemEntity> _files;
        _files = _dir.listSync(recursive: true, followLinks: false);
        for (FileSystemEntity entity in _files) {
          String path = entity.path;
          if (path.endsWith('.jpg'))
            _selectedFiles.add(CustomFile(
                file: entity, isSelected: false, type: FileType.IMAGE));
        }

        setState(() {
          _isLoading = false;
          _imageMode = true;
        });
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        print(e);
      }
    }
  }

  _handleTab() async {
    if (_tabController.index == 0) {
      await _fetchApps();
    } else if (_tabController.index == 1) {
      await _fetchVideos();
    } else if (_tabController.index == 2) {
      await _fetchMusic();
    } else if (_tabController.index == 3) {
      await _fetchImages();
    }
  }

  _sendPayload(File file) async {
    if (file == null) return;

    int payloadId = await Nearby().sendFilePayload(cId, file.path);
    showSnackbar("Sending file to $cId");
    Nearby().sendBytesPayload(
        cId,
        Uint8List.fromList(
            "$payloadId:${file.path.split('/').last}".codeUnits));
    _sendFiles.removeWhere((element) => element.file.path == file.path);
  }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_handleTab);
    _init();

    _streamController.stream.listen((event) async {
      if (!event) {
        // send next
        if (_sendFiles.length > 0) {
          if (_sendFiles[0].type == FileType.APK) {
            await _sendPayload(
                File(_sendFiles[0].applicationWithIcon.apkFilePath));
          } else {
            await _sendPayload(_sendFiles[0].file);
          }
        } else {
          setState(() {
            _sending = false;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: AbsorbPointer(
        absorbing: _sending,
        child: Scaffold(
            key: _scaffoldKey,
            drawer: Container(
              width: MediaQuery.of(context).size.width / 1.5,
              child: Drawer(
                child: Container(
                  child: ListView(
                    children: <Widget>[
                      Container(
                        padding: EdgeInsets.all(20),
                        child: Stack(
                          children: <Widget>[
                            Center(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  Stack(
                                    children: <Widget>[
                                      CircleAvatar(
                                        minRadius: 40,
                                        maxRadius: 40,
                                      ),
                                    ],
                                  ),
                                  SizedBox(
                                    height: 5,
                                  ),
                                  Text(
                                    "SOME TEXT",
                                    style: TextStyle(color: Colors.blue[900]),
                                  ),
                                  RaisedButton(
                                    color: Colors.purple,
                                    onPressed: () {},
                                    child: Text("SIGN IN"),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.all(
                                            Radius.circular(12))),
                                  )
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.settings,
                        ),
                        title: Text("Settings"),
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.share,
                        ),
                        title: Text("Web Share"),
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.person_add,
                        ),
                        title: Text("Invite friends to install Sharer App"),
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.help,
                        ),
                        title: Text("Help & Feedback"),
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.done,
                        ),
                        title: Text("Weekly summary"),
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.info,
                        ),
                        title: Text("About Us"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            appBar: AppBar(
              backgroundColor: Colors.white,
              leading: IconButton(
                  icon: Icon(
                    Icons.menu,
                    color: Colors.black,
                  ),
                  onPressed: () {
                    _scaffoldKey.currentState.openDrawer();
                  }),
              actions: <Widget>[
                IconButton(
                    icon: Icon(
                      Icons.rotate_left,
                      color: Colors.black,
                    ),
                    onPressed: () {}),
                IconButton(
                    icon: Icon(
                      Icons.fullscreen,
                      color: Colors.black,
                    ),
                    onPressed: () {}),
                IconButton(
                    icon: Icon(
                      Icons.send,
                      color: Colors.black,
                    ),
                    onPressed: () {}),
              ],
              bottom: TabBar(
                controller: _tabController,
                labelColor: Colors.black,
                indicatorColor: Colors.black,
                tabs: [
                  Tab(
                    text: "Apps",
                  ),
                  Tab(
                    text: "Videos",
                  ),
                  Tab(
                    text: "Music",
                  ),
                  Tab(
                    text: "Pictures",
                  ),
                ],
              ),
            ),
            body: _isLoading
                ? Center(
                    child: CircularProgressIndicator(),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _appsTab(),
                      _videosTab(),
                      _musicTab(),
                      _imageTab(),
                    ],
                  )),
      ),
    );
  }

  _musicTab() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Stack(
        children: <Widget>[
          Container(
            height: MediaQuery.of(context).size.height * 0.75,
            child: ListView(
              children: List.generate(_selectedFiles.length, (index) {
                var app = _selectedFiles[index];

                if (!(app.type == FileType.MUSIC)) {
                  return Container();
                }

                return Stack(
                  children: <Widget>[
                    _selectedMode
                        ? Positioned(
                            child: Icon(
                              app.isSelected
                                  ? Icons.done
                                  : Icons.add_circle_outline,
                              color: Colors.blue,
                            ),
                            top: 0,
                            right: 0,
                          )
                        : Container(),
                    ListTile(
                      onTap: () {
                        setState(() {
                          app.isSelected = !app.isSelected;
                          if (app.isSelected) {
                            _sendFiles.add(app);
                          } else {
                            _sendFiles.removeWhere(
                                (el) => el.file.path == app.file.path);
                          }
                          _selectedMode = true;
                        });
                      },
                      leading: Icon(Icons.music_note),
                      title: Text(app.file.path.split('/').last),
                    ),
                  ],
                );
              }),
            ),
          ),
          _bottomButtons()
        ],
      ),
    );
  }

  _imageTab() {
    var images = _selectedFiles
        .where((element) => element.type == FileType.IMAGE)
        .toList();
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Stack(
        children: <Widget>[
          Container(
            height: MediaQuery.of(context).size.height * 0.75,
            child: GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 0,
              children: List.generate(images.length, (index) {
                var app = images[index];

                return Stack(
                  children: <Widget>[
                    _selectedMode
                        ? Positioned(
                            child: Icon(
                              app.isSelected
                                  ? Icons.done
                                  : Icons.add_circle_outline,
                              color: Colors.blue,
                            ),
                            top: 0,
                            right: 0,
                          )
                        : Container(),
                    GestureDetector(
                      onTap: () {
                        _selectedFiles.forEach((element) {
                          if (element.type == FileType.IMAGE &&
                              element.file.path == app.file.path) {
                            element.isSelected = !element.isSelected;
                            if (element.isSelected) {
                              _sendFiles.add(element);
                            } else {
                              _sendFiles.removeWhere(
                                  (el) => el.file.path == element.file.path);
                            }
                          }
                        });
                        _selectedMode = true;
                        setState(() {});
                      },
                      child: Container(
                        width: 150,
                        height: 100,
                        padding: EdgeInsets.only(left: 8, right: 8),
                        child: Column(
                          children: <Widget>[
                            Container(
                              width: 120,
                              height: 60,
                              child: Image.file(
                                app.file,
                                cacheHeight: 100,
                                cacheWidth: 100,
                              ),
                            ),
                            Text(
                              app.file.path.split('/').last,
                              style: TextStyle(fontSize: 9),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
          _bottomButtons(),
        ],
      ),
    );
  }

  _videosTab() {
    var videos = _selectedFiles
        .where((element) => element.type == FileType.VIDEO)
        .toList();
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Stack(
        children: <Widget>[
          Container(
            height: MediaQuery.of(context).size.height * 0.75,
            child: GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 0,
              children: List.generate(videos.length, (index) {
                var app = videos[index];

                return Stack(
                  children: <Widget>[
                    _selectedMode
                        ? Positioned(
                            child: Icon(
                              app.isSelected
                                  ? Icons.done
                                  : Icons.add_circle_outline,
                              color: Colors.blue,
                            ),
                            top: 0,
                            right: 0,
                          )
                        : Container(),
                    GestureDetector(
                        onTap: () {
                          _selectedFiles.forEach((element) {
                            if (element.type == FileType.VIDEO &&
                                element.file.path == app.file.path) {
                              element.isSelected = !element.isSelected;
                              if (element.isSelected) {
                                _sendFiles.add(element);
                              } else {
                                _sendFiles.removeWhere(
                                    (el) => el.file.path == element.file.path);
                              }
                            }
                          });

                          _selectedMode = true;
                          setState(() {});
                        },
                        child: VideoWidget(video: app.file)),
                  ],
                );
              }),
            ),
          ),
          _bottomButtons(),
        ],
      ),
    );
  }

  _appsTab() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Stack(
        children: <Widget>[
          Container(
            height: MediaQuery.of(context).size.height * 0.75,
            child: GridView.count(
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              children: List.generate(_selectedFiles.length, (index) {
                var app = _selectedFiles[index];

                if (!(app.type == FileType.APK)) {
                  return Container();
                }

                return Stack(
                  children: <Widget>[
                    _selectedMode
                        ? Positioned(
                            child: Icon(
                              app.isSelected
                                  ? Icons.done
                                  : Icons.add_circle_outline,
                              color: Colors.blue,
                            ),
                            top: 0,
                            right: 0,
                          )
                        : Container(),
                    ListTile(
                      onTap: () {
                        setState(() {
                          app.isSelected = !app.isSelected;
                          if (app.isSelected) {
                            _sendFiles.add(app);
                          } else {
                            _sendFiles.removeWhere(
                                (el) => el.file.path == app.file.path);
                          }
                          _selectedMode = true;
                        });
                      },
                      title: Image.memory(app.applicationWithIcon.icon),
                      subtitle: Text(
                        app.applicationWithIcon.appName,
                        style: TextStyle(fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
          _bottomButtons()
        ],
      ),
    );
  }

  _bottomButtons() {
    return Positioned(
      width: MediaQuery.of(context).size.width * 0.7,
      height: MediaQuery.of(context).size.height * 0.1,
      bottom: 75,
      left: MediaQuery.of(context).size.width / 2 -
          (MediaQuery.of(context).size.width * 0.35),
      child: Material(
        elevation: 10,
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
              color: Colors.grey, borderRadius: BorderRadius.circular(12)),
          child: OverLayClass(
            value: _selectedMode,
            onRecieveClick: () async {
              await _askPermissions();
              _advertiseConnection();
            },
            onSendClick: () async {
              await _askPermissions();
              _discoverConnection();
            },
            onSendFile: () async {
              setState(() {
                _sending = true;
              });

              if (_sendFiles.length > 0) {
                if (_sendFiles[0].type == FileType.APK) {
                  await _sendPayload(_sendFiles[0].file);
                } else {
                  await _sendPayload(_sendFiles[0].file);
                }
              }
            },
          ),
        ),
      ),
    );
  }
}

class VideoWidget extends StatefulWidget {
  final File video;
  VideoWidget({Key key, @required this.video}) : super(key: key);

  @override
  _VideoWidgetState createState() => _VideoWidgetState();
}

class _VideoWidgetState extends State<VideoWidget> {
  // VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    // _controller = VideoPlayerController.network(widget.video.path)
    //   ..initialize().then((_) {
    //     setState(() {}); //when your thumbnail will show.
    //   });
  }

  @override
  void dispose() {
    super.dispose();
    // _controller?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      height: 100,
      padding: EdgeInsets.only(left: 8, right: 8),
      child: Column(
        children: <Widget>[
          Container(
            width: 120,
            height: 60,
            color: Colors.black,
          ),
          Text(
            widget.video.path.split('/').last,
            style: TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
  }
}

class OverLayClass extends StatefulWidget {
  final bool value;
  Function onSendClick;
  Function onRecieveClick;
  Function onSendFile;

  OverLayClass(
      {Key key,
      this.value,
      this.onRecieveClick,
      this.onSendClick,
      this.onSendFile})
      : super(key: key);

  @override
  _OverLayClassState createState() => _OverLayClassState();
}

class _OverLayClassState extends State<OverLayClass> {
  @override
  Widget build(BuildContext context) {
    if (widget.value) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          RaisedButton(
            textColor: Colors.white,
            child: Text("SEND FILES"),
            onPressed: widget.onSendFile,
            color: Colors.blue,
          )
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: <Widget>[
        GestureDetector(
          onTap: widget.onSendClick,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                height: MediaQuery.of(context).size.height * 0.05,
                child: Image.asset('assets/send.png'),
              ),
              SizedBox(
                height: 5,
              ),
              Text(
                "SEND",
                style: Theme.of(context).textTheme.bodyText1,
              )
            ],
          ),
        ),
        GestureDetector(
          onTap: widget.onRecieveClick,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                height: MediaQuery.of(context).size.height * 0.05,
                child: Image.asset('assets/recieve.png'),
              ),
              SizedBox(
                height: 5,
              ),
              Text(
                "Recieve",
                style: Theme.of(context).textTheme.bodyText1,
              )
            ],
          ),
        ),
      ],
    );
  }
}

enum FileType { APK, MUSIC, VIDEO, IMAGE }

class CustomFile {
  bool isSelected = false;
  FileType type;
  File file;
  ApplicationWithIcon applicationWithIcon;

  CustomFile({this.isSelected, this.file, this.applicationWithIcon, this.type});
}
