# iSCP 2.0 Client Library for C#

iSCP Client for C# は、iSCP version 2を用いたリアルタイムAPIにアクセスするためのクライアントライブラリです。

## Requirements

- .NET Standard 2.0

## Dependencies

- [Google.Protobuf](https://github.com/protocolbuffers/protobuf)

## Installation for Unity

Unityへのインポートはパッケージマネージャーから可能です。

パッケージマネージャーの `Add Package from Git URL...` で表示されるテキストボックスに

```
https://github.com/aptpod/iscp-csharp.git?path=/package
```

を入力しインポートを行ってください。

## Implementation

### Connect to intdash API

このサンプルではiscp-csharpを使ってintdash APIに接続します。

```csharp
using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

// iSCPをインポート。
using iSCP;
using iSCP.Model;
using iSCP.Transport;

public partial class ExampleForUnity : MonoBehaviour, IConnectionCallbacks
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

    void Connect()
    {
        // WebSocketを使って接続するように指定します。
        ITransportConfig transportConfig = new WebSocket.Config();
        Connection.Connect(
            address: targetServer, 
            transportConfig: transportConfig, 
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

### Start Downstream

アップストリームで送信されたデータをダウンストリームで受信するサンプルです。

このサンプルでは、アップストリーム開始のメタデータ、基準時刻のメタデータ、文字列型のデータポイントを受信しています。

```csharp
public partial class ExampleForUnity : IDownstreamCallbacks
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

    void StartDownstream()
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
        Debug.Log($"Received dataPoints sequenceNumber[{message.SequenceNumber}], sessionId[{message.UpstreamInfo.SessionId}]");
        foreach (var g in message.DataPointGroups)
        {
            foreach (var dp in g.DataPoints)
            {
                Debug.Log($"Received a dataPoint dataName[{g.DataId.Name}], dataType[{g.DataId.Type}], payload[{System.Text.Encoding.UTF8.GetString(dp.Payload)}]");
            }
        }
    }

    public void OnReceiveMetadata(Downstream downstream, DownstreamMetadata message)
    {
        // メタデータを受信した際にコールされます。
        Debug.Log($"Received a metadata sourceNodeId[{message.SourceNodeId}], metadataType:{message.Type}");
        switch (message.Type)
        {
            case DownstreamMetadata.MetadataType.BaseTime:
                var baseTime = message.BaseTime.Value;
                Debug.Log($"Received baseTime[{new DateTime(baseTime.BaseTime_)}], priority[{baseTime.Priority}], name[{baseTime.Priority}]");
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

### Start Upstream

アップストリームの送信サンプルです。

このサンプルでは、基準時刻のメタデータと、文字列型のデータポイントをiSCPサーバーへ送信しています。

```csharp
public partial class ExampleForUnity : IUpstreamCallbacks
{
    /// <summary>
    /// 送信するデータを永続化するかどうか
    /// </summary>
    bool upstreamPersist = false;
    /// <summary>
    /// オープンしたストリーム一覧
    /// </summary>
    List<Upstream> upstreams = new List<Upstream>();

    void StartUpstream()
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

                var baseTime = DateTime.UtcNow.Ticks; // 基準時刻です。

                // 基準時刻をiSCPサーバーへ送信します。
                connection?.SendBaseTime(
                    baseTime: new BaseTime(
                        sessionId: sessionId,
                        name: "manual",
                        priority: 1000,
                        elapsedTime: 0,
                        baseTime: baseTime),
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
                                elapsedTime: DateTime.UtcNow.Ticks - baseTime, // 基準時刻からの経過時間をデータポイントの経過時間として打刻します。
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

## References
- [APIリファレンス](https://docs.intdash.jp/api/intdash-sdk/csharp/latest/)
  - 過去のバージョンのリファレンスは [こちら](https://docs.intdash.jp/api/intdash-sdk/csharp-versions)
- [Github](https://github.com/aptpod/iscp-cs)