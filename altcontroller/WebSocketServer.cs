using System;
using System.Collections.Concurrent;
using System.Net;
using System.Net.WebSockets;
using System.Threading;
using System.Threading.Tasks;

namespace AltControllerWebSocketServer
{
    class Program
    {
        private static ConcurrentDictionary<WebSocket, SemaphoreSlim> _clients = new ConcurrentDictionary<WebSocket, SemaphoreSlim>();

        static void Main(string[] args)
        {
            try
            {
                RunServerAsync().Wait();
            }
            catch (Exception ex)
            {
                Console.WriteLine("[Secret Service] Fatal Error: " + ex.Message);
                Console.ReadLine();
            }
        }

        static async Task RunServerAsync()
        {
            int port = 8080;
            HttpListener listener = new HttpListener();
            listener.Prefixes.Add(string.Format("http://localhost:{0}/", port));
            
            Console.WriteLine(string.Format("[Secret Service] Starting WebSocket server on port {0} (Optimized Fast Mode)...", port));
            listener.Start();
            Console.WriteLine("[Secret Service] Server is running. Waiting for connections...");

            while (true)
            {
                HttpListenerContext context = await listener.GetContextAsync();
                
                if (context.Request.IsWebSocketRequest)
                {
                    // Fire and forget, no await to allow accepting next connections instantly
                    var _ = ProcessRequestAsync(context);
                }
                else
                {
                    context.Response.StatusCode = 400;
                    context.Response.Close();
                }
            }
        }

        private static async Task ProcessRequestAsync(HttpListenerContext context)
        {
            HttpListenerWebSocketContext webSocketContext = null;

            try
            {
                webSocketContext = await context.AcceptWebSocketAsync(null);
            }
            catch
            {
                context.Response.StatusCode = 500;
                context.Response.Close();
                return;
            }

            WebSocket webSocket = webSocketContext.WebSocket;
            _clients.TryAdd(webSocket, new SemaphoreSlim(1, 1));

            byte[] receiveBuffer = new byte[1024];

            try
            {
                while (webSocket.State == WebSocketState.Open)
                {
                    WebSocketReceiveResult receiveResult = await webSocket.ReceiveAsync(new ArraySegment<byte>(receiveBuffer), CancellationToken.None);

                    if (receiveResult.MessageType == WebSocketMessageType.Close)
                    {
                        await webSocket.CloseAsync(WebSocketCloseStatus.NormalClosure, "", CancellationToken.None);
                    }
                    else if (receiveResult.MessageType == WebSocketMessageType.Text)
                    {
                        // Copy payload to avoid overwrite
                        int count = receiveResult.Count;
                        byte[] messageBytes = new byte[count];
                        Buffer.BlockCopy(receiveBuffer, 0, messageBytes, 0, count);
                        ArraySegment<byte> segment = new ArraySegment<byte>(messageBytes);

                        // Broadcast concurrently (fire-and-forget for minimal latency)
                        foreach (var kvp in _clients)
                        {
                            var client = kvp.Key;
                            var gate = kvp.Value;
                            if (client.State == WebSocketState.Open)
                            {
                                var task = System.Threading.Tasks.Task.Run(async () =>
                                {
                                    await gate.WaitAsync();
                                    try { await client.SendAsync(segment, WebSocketMessageType.Text, true, CancellationToken.None); }
                                    catch { }
                                    finally { gate.Release(); }
                                });
                            }
                        }
                    }
                }
            }
            catch
            {
                // Ignore disconnect exceptions gracefully
            }
            finally
            {
                if (webSocket != null)
                {
                    SemaphoreSlim sem;
                    if (_clients.TryRemove(webSocket, out sem)) sem.Dispose();
                    webSocket.Dispose();
                }
            }
        }
    }
}
