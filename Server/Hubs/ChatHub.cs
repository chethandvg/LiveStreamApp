using Microsoft.AspNetCore.SignalR;
using System.Collections.Concurrent;

namespace Server.Hubs
{
    public class ChatHub : Hub
    {
        // Track users in each stream
        private static readonly ConcurrentDictionary<string, HashSet<string>> _streamViewers = new();
        private static readonly ConcurrentDictionary<string, string> _connectionToUser = new();

        public async Task JoinStream(string streamId, string username)
        {
            await Groups.AddToGroupAsync(Context.ConnectionId, streamId);

            _connectionToUser[Context.ConnectionId] = username;

            if (!_streamViewers.ContainsKey(streamId))
            {
                _streamViewers[streamId] = new HashSet<string>();
            }
            _streamViewers[streamId].Add(username);

            // Notify others that user joined
            await Clients.Group(streamId).SendAsync("UserJoined", username, _streamViewers[streamId].Count);

            // Send viewer count to new user
            await Clients.Caller.SendAsync("ViewerCount", _streamViewers[streamId].Count);
        }

        public async Task LeaveStream(string streamId)
        {
            if (_connectionToUser.TryGetValue(Context.ConnectionId, out var username))
            {
                await Groups.RemoveFromGroupAsync(Context.ConnectionId, streamId);

                if (_streamViewers.ContainsKey(streamId))
                {
                    _streamViewers[streamId].Remove(username);

                    // Notify others that user left
                    await Clients.Group(streamId).SendAsync("UserLeft", username, _streamViewers[streamId].Count);
                }

                _connectionToUser.TryRemove(Context.ConnectionId, out _);
            }
        }

        public async Task SendMessage(string streamId, string message)
        {
            if (_connectionToUser.TryGetValue(Context.ConnectionId, out var username))
            {
                var timestamp = DateTime.UtcNow;

                // Broadcast message to all users in this stream
                await Clients.Group(streamId).SendAsync("ReceiveMessage",
                    username,
                    message,
                    timestamp.ToString("HH:mm:ss"));
            }
        }

        public async Task SendReaction(string streamId, string reactionType)
        {
            if (_connectionToUser.TryGetValue(Context.ConnectionId, out var username))
            {
                // Broadcast reaction to all users in stream (for emoji reactions, likes, etc.)
                await Clients.Group(streamId).SendAsync("ReceiveReaction",
                    username,
                    reactionType);
            }
        }

        public override async Task OnDisconnectedAsync(Exception? exception)
        {
            // Clean up when user disconnects
            if (_connectionToUser.TryGetValue(Context.ConnectionId, out var username))
            {
                foreach (var stream in _streamViewers)
                {
                    if (stream.Value.Contains(username))
                    {
                        stream.Value.Remove(username);
                        await Clients.Group(stream.Key).SendAsync("UserLeft", username, stream.Value.Count);
                    }
                }

                _connectionToUser.TryRemove(Context.ConnectionId, out _);
            }

            await base.OnDisconnectedAsync(exception);
        }
    }
}
