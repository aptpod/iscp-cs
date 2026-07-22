# iSCP 2.0 Client Library for C#

iSCP Client for C# は、iSCP version 2を用いたリアルタイムAPIにアクセスするためのクライアントライブラリです。

## Requirements

- .NET Standard 2.0

## Dependencies

- [Google.Protobuf](https://github.com/protocolbuffers/protobuf)

## Installation

### .NET

NuGetからインストールできます。

.NET CLIを使用する場合は、プロジェクトのディレクトリで次のコマンドを実行します。

```shell
dotnet add package iSCP
```

Visual Studioのパッケージマネージャーコンソールを使用する場合は、次のコマンドを実行します。

```powershell
Install-Package iSCP
```

プロジェクトファイルへ直接追加する場合は、次の `PackageReference` を記述します。

```xml
<ItemGroup>
  <PackageReference Include="iSCP" Version="1.3.0" />
</ItemGroup>
```

### Unity

Unityへのインポートはパッケージマネージャーから可能です。

パッケージマネージャーの `Add Package from Git URL...` で表示されるテキストボックスに

```text
https://github.com/aptpod/iscp-cs.git?path=/package
```

を入力しインポートを行ってください。

## Implementation

### Connect to intdash API

このサンプルではiscp-csを使ってintdash APIに接続します。

```csharp
// iSCPをインポート。
using iSCP;
using iSCP.Model;
using iSCP.Transport;

public partial class Example : IConnectionCallbacks
{
    /// <summary>
    /// 接続するintdashサーバー
    /// </summary>
    string targetServer = "https://example.com";
    /// <summary>
    /// ノードUUID（ここで指定されたノードとして送受信を行います。
    /// intdash APIでノードを生成した際に発行されたノードUUIDを指定します。）
    /// </summary>
    string nodeId = "00000000-0000-0000-0000-000000000000";
    /// <summary>
    /// アクセストークン
    /// <para>intdash APIで取得したアクセストークンを指定して下さい。</para>
    /// </summary>
    string accessToken = "";
    /// <summary>
    /// コネクション
    /// </summary>
    Connection connection;

    public void Connect(Action onConnected = null)
    {
        // 接続情報のセットアップをします。
        var urls = targetServer.Split(new string[] { "://" }, StringSplitOptions.None);
        string address;
        var enableTls = false;
        if (urls.Length == 1)
        {
            address = urls[0];
        }
        else
        {
            enableTls = urls[0] == "https";
            address = urls[1];
        }
        // WebSocketを使って接続するように指定します。
        IConnector connector = new WebSocketConnector(enableTls: enableTls);
        Connection.Connect(
            address: address,
            connector: connector,
            tokenSource: (token) =>
            {
                // アクセス用のトークンを指定します。接続時に発生するイベントにより使用されます。
                // ここでは固定のトークンを返していますが随時トークンの更新を行う実装にするとトークンの期限切れを考える必要がなくなります。
                token(accessToken);
            },
            nodeId: nodeId,
            completion: (con, exception) =>
            {
                if (!(con is Connection connection))
                {
                    // 接続失敗。
                    return;
                }
                // 接続成功。
                this.connection = connection;
                connection.Callbacks = this; // IConnectionCallbacks
                // 以降、StartUpstreamやStartDownstreamなどが実行可能になります。
                onConnected?.Invoke();
            });
    }

    #region IConnectionCallbacks

    public void OnReconnect(Connection connection)
    {
        // Connectionが再オープンされた際にコールされます。
    }

    public void OnDisconnect(Connection connection)
    {
        // Connectionがクローズされた際にコールされます。
    }

    public void OnFailWithError(Connection connection, Exception error)
    {
        // Connection内部で何らかのエラーが発生した際にコールされます。
    }

    #endregion
}
```

### Start Upstream

アップストリームの送信サンプルです。

このサンプルでは、基準時刻のメタデータと、文字列型のデータポイントをiSCPサーバーへ送信しています。

```csharp
public partial class Example : IUpstreamCallbacks
{
    /// <summary>
    /// 送信するデータを永続化するかどうか
    /// </summary>
    bool upstreamPersist = false;
    /// <summary>
    /// オープンしたストリーム一覧
    /// </summary>
    List<Upstream> upstreams = new List<Upstream>();

    public void StartUpstream()
    {
        // セッションIDを払い出します。
        var sessionId = Guid.NewGuid().ToString().ToLower();

        // Upstreamをオープンします。
        connection?.OpenUpstream(
            sessionId: sessionId,
            persist: upstreamPersist,
            completion: (upstream, exception) =>
            {
                if (upstream == null)
                {
                    // オープン失敗。
                    return;
                }
                // オープン成功。
                upstreams.Add(upstream);

                // 送信するデータポイントを保存したい場合や、アップストリームのエラーをハンドリングしたい場合はコールバックを設定します。
                upstream.Callbacks = this; // IUpstreamCallbacks

                var baseTime = DateTime.UtcNow; // 基準時刻です。

                // 基準時刻をiSCPサーバーへ送信します。
                connection?.SendBaseTime(
                    baseTime: new BaseTime(
                        sessionId: sessionId,
                        name: "manual",
                        priority: 60,
                        elapsedTime: 0,
                        baseTime: baseTime.ToUnixTimeTicks()), // 送信する基準時刻はUNIX時刻である必要があります。
                    persist: upstreamPersist,
                    completion: (sendBaseTimeEx) =>
                    {
                        if (sendBaseTimeEx != null)
                        {
                            // 基準時刻の送信に失敗。
                            return;
                        }
                        // 基準時刻の送信に成功。

                        // 文字列型のデータポイントをiSCPサーバーへ送信します。
                        upstream.WriteDataPoint(
                                dataId: new DataId(
                                    name: "greeting",
                                    type: "string"),
                                dataPoint: new DataPoint(
                                    elapsedTime: DateTime.UtcNow.Ticks - baseTime.Ticks, // 基準時刻からの経過時間をデータポイントの経過時間として打刻します。
                                    payload: System.Text.Encoding.UTF8.GetBytes("hello")));
                    });
            });
    }

    #region IUpstreamCallbacks

    public void OnGenerateChunk(Upstream upstream, UpstreamChunk message)
    {
        // バッファへ書き込んだデータポイントが実際に送信される直前にコールされます。
    }

    public void OnReceiveAck(Upstream upstream, UpstreamChunkAck message)
    {
        // データポイントの送信後に返却されるACKを受信できた場合にコールされます。
    }

    public void OnFailWithError(Upstream upstream, Exception error)
    {
        // 内部でエラーが発生した場合にコールされます。
    }

    public void OnCloseWithError(Upstream upstream, Exception error)
    {
        // 何らかの理由でストリームがクローズした場合にコールされます。
        // 再度アップストリームをオープンしたい場合は、 `Connection.ReopenUpstream()` を使用することにより、ストリームの設定を引き継いで別のストリームを開くことが可能です。
    }

    public void OnResume(Upstream upstream)
    {
        // 自動再接続機能が働き、再接続が行われた場合にコールされます。
    }

    #endregion
}
```

### Start Downstream

アップストリームで送信されたデータをダウンストリームで受信するサンプルです。

このサンプルでは、アップストリーム開始のメタデータ、基準時刻のメタデータ、文字列型のデータポイントを受信しています。

```csharp
public partial class Example : IDownstreamCallbacks
{
    /// <summary>
    /// 受信したいデータを送信している送信元ノードのUUID
    /// （アップストリームを行っている送信元でConnection.Configで設定したnodeIdを指定してください。）
    /// </summary>
    string targetDownstreamNodeId = "00000000-0000-0000-0000-000000000000";
    /// <summary>
    /// オープンしたダウンストリーム一覧
    /// </summary>
    List<Downstream> downstreams = new List<Downstream>();

    public void StartDownstream()
    {
        // ダウンストリームをオープンします。
        connection?.OpenDownstream(
            downstreamFilters: new DownstreamFilter[]
            {
                new DownstreamFilter(
                    sourceNodeId: targetDownstreamNodeId, // 送信元ノードのIDを指定します。
                    dataFilters: new DataFilter[]
                    {
                        new DataFilter(
                            name: "#", type: "#") // 受信したいデータを名称と型で指定します。この例では、ワイルドカード `#` を使用して全てのデータを取得します。
                    })
            },
            completion: (downstream, exception) =>
            {
                if (downstream == null)
                {
                    // オープン失敗。
                    return;
                }
                // オープン成功。
                downstreams.Add(downstream);
                // 受信データを取り扱うためにデリゲートを設定します。
                downstream.Callbacks = this; // IDownstreamCallbacks
            });
    }

    #region IDownstreamCallbacks


    public void OnReceiveChunk(Downstream downstream, DownstreamChunk message)
    {
        // データポイントを読み込むことができた際にコールされます。
        Console.WriteLine($"Received dataPoints sequenceNumber[{message.SequenceNumber}], sessionId[{message.UpstreamInfo.SessionId}]");
        foreach (var g in message.DataPointGroups)
        {
            foreach (var dp in g.DataPoints)
            {
                Console.WriteLine($"Received a dataPoint dataName[{g.DataId.Name}], dataType[{g.DataId.Type}], payload[{System.Text.Encoding.UTF8.GetString(dp.Payload)}]");
            }
        }
    }

    public void OnReceiveMetadata(Downstream downstream, DownstreamMetadata message)
    {
        // メタデータを受信した際にコールされます。
        Console.WriteLine($"Received a metadata sourceNodeId[{message.SourceNodeId}], metadataType:{message.Type}");
        switch (message.Type)
        {
            case DownstreamMetadata.MetadataType.BaseTime:
                var baseTime = message.BaseTime.Value;
                Console.WriteLine($"Received baseTime[{baseTime.BaseTime_.ToDateTimeFromUnixTimeTicks()}], priority[{baseTime.Priority}], name[{baseTime.Name}]");
                break;
            default: break;
        }
    }

    public void OnFailWithError(Downstream downstream, Exception error)
    {
        // 内部でエラーが発生した場合にコールされます。
    }

    public void OnCloseWithError(Downstream downstream, Exception error)
    {
        // 何らかの理由でストリームがクローズした場合にコールされます。
        // 再度ダウンストリームをオープンしたい場合は、 `Connection.ReopenDownstream()` を使用することにより、ストリームの設定を引き継いで別のストリームを開くことが可能です。
    }

    public void OnResume(Downstream downstream)
    {
        // 自動再接続機能が働き、再接続が行われた場合にコールされます。
    }

    #endregion
}
```

### E2E Call

E2E（エンドツーエンド）コールのサンプルです。

コントローラノードが対象ノードに対して指示を出し、対象ノードは受信完了のリプライを行う簡単なサンプルです。

```csharp
// iSCPをインポート。
using iSCP;
using iSCP.Transport;
using iSCP.Model;

public partial class E2ECallExample
{
    /// <summary>
    /// 接続するintdashサーバー
    /// </summary>
    string targetServer = "https://example.com";

    /// <summary>
    /// コントローラーノードのUUID
    /// </summary>
    string controllerNodeId = "00000000-0000-0000-0000-000000000000";
    /// <summary>
    /// 対象ノードのUUID
    /// </summary>
    string targetNodeId = "11111111-1111-1111-1111-111111111111";

    /// <summary>
    /// コントローラーノード用のアクセストークン
    /// <para>intdash APIで取得したアクセストークンを指定して下さい。</para>
    /// </summary>
    string accessTokenForController = "";
    /// <summary>
    /// 対象ノード用のアクセストークン
    /// <para>intdash APIで取得したアクセストークンを指定して下さい。</para>
    /// </summary>
    string accessTokenForTarget = "";

    /// <summary>
    /// コントローラーノード用のコネクション
    /// </summary>
    Connection connectionForController;
    /// <summary>
    /// 対象ノード用のコネクション
    /// </summary>
    Connection connectionForTarget;
}

// コントローラーノードからメッセージを送信するサンプルです。このサンプルでは文字列メッセージを対象ノードに対して送信し、対象ノードからのリプライを待ちます。
public partial class E2ECallExample
{

    public void ConnectForController(Action onConnected = null)
    {
        // 接続情報のセットアップをします。
        var urls = targetServer.Split(new string[] { "://" }, StringSplitOptions.None);
        string address;
        var enableTls = false;
        if (urls.Length == 1)
        {
            address = urls[0];
        }
        else
        {
            enableTls = urls[0] == "https";
            address = urls[1];
        }
        // WebSocketを使って接続するように指定します。
        IConnector connector = new WebSocketConnector(enableTls: enableTls);
        Connection.Connect(
            address: address,
            connector: connector,
            tokenSource: (token) =>
            {
                // アクセストークンを指定します。接続時に発生するイベントにより使用されます。
                // ここでは固定のトークンを返していますが、随時トークンの更新を行う実装にするとトークンの期限切れを考える必要がなくなります。
                token(accessTokenForController);
            },
            nodeId: controllerNodeId,
            completion: (con, exception) =>
            {
                if (!(con is Connection connection))
                {
                    // 接続失敗。
                    return;
                }
                // 接続成功。
                this.connectionForController = connection;
                onConnected?.Invoke();
            });
    }

    public void SendCall()
    {
        // コールを送信し、リプライコールを受信するとコールバックが発生します。
        connectionForController?.SendCallAndWaitReplyCall(
            new UpstreamCall(
                destinationNodeId: targetNodeId,
                name: "greeting",
                type: "string",
                payload: System.Text.Encoding.UTF8.GetBytes("hello")), completion: (downstreamReplyCall, exception) =>
                {
                    if (exception != null)
                    {
                        // コールの送信もしくはリプライの受信に失敗。
                        return;
                    }
                    // コールの送信及びリプライの受信に成功。
                });
    }

}

// コントローラーノードからのコールを受け付け、すぐにリプライするサンプルです。
public partial class E2ECallExample : IConnectionE2ECallCallbacks
{

    public void ConnectForTarget(Action onConnected = null)
    {
        // 接続情報のセットアップをします。
        var urls = targetServer.Split(new string[] { "://" }, StringSplitOptions.None);
        string address;
        var enableTls = false;
        if (urls.Length == 1)
        {
            address = urls[0];
        }
        else
        {
            enableTls = urls[0] == "https";
            address = urls[1];
        }
        // WebSocketを使って接続するように指定します。
        IConnector connector = new WebSocketConnector(enableTls: enableTls);
        Connection.Connect(
            address: address,
            connector: connector,
            tokenSource: (token) =>
            {
                // アクセス用のトークンを指定します。接続時に発生するイベントにより使用されます。
                // ここでは固定のトークンを返していますが、随時トークンの更新を行う実装にするとトークンの期限切れを考える必要がなくなります。
                token(accessTokenForTarget);
            },
            nodeId: targetNodeId,
            completion: (con, exception) =>
            {
                if (!(con is Connection connection))
                {
                    // 接続失敗。
                    return;
                }
                // 接続成功。
                this.connectionForTarget = connection;
                // DownstreamCallの受信を監視するためにコールバックを設定します。
                connection.E2ECallCallbacks = this; // IConnectionE2ECallCallbacks
                onConnected?.Invoke();
            });
    }

    #region IConnectionE2ECallCallbacks

    public void OnReceiveCall(Connection connection, DownstreamCall downstreamCall)
    {
        // DownstreamCallを受信した際にコールされます。
        // このサンプルではDownstreamCallを受信したらすぐにリプライコールを送信します。
        connection.SendReplyCall(
            upstreamReplyCall:
            new UpstreamReplyCall(
                requestCallId: downstreamCall.CallId,
                destinationNodeId: downstreamCall.SourceNodeId,
                name: "reply_greeting",
                type: "string",
                payload: System.Text.Encoding.UTF8.GetBytes("world")), completion: (exception) =>
                {
                    if (exception != null)
                    {
                        // リプライコールの送信に失敗。
                        return;
                    }
                    // リプライコールの送信に成功。
                });
    }

    public void OnReceiveReplyCall(Connection connection, DownstreamReplyCall downstreamReplyCall)
    {
        // DownstreamReplyCallを受信した際にコールされます。
    }

    #endregion
}
```

## References
- [APIリファレンス](https://docs.intdash.jp/api/intdash-sdk/csharp/latest/)
  - 過去のバージョンのリファレンスは [こちら](https://docs.intdash.jp/api/intdash-sdk/csharp-versions)
- [GitHub](https://github.com/aptpod/iscp-cs)
