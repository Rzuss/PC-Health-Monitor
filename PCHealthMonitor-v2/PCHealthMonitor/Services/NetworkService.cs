using PCHealthMonitor.ViewModels;
using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Threading.Tasks;

namespace PCHealthMonitor.Services;

public sealed class NetworkService
{
    private static readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(5) };

    public async Task<NetworkScanResult> ScanAsync()
    {
        var result = new NetworkScanResult();

        // CRITICAL FIX: all synchronous network operations moved to Task.Run so they
        // never block the UI thread. Previously, GetAllNetworkInterfaces() and
        // GetActiveTcpConnections() ran synchronously on the UI thread, causing freezes
        // and potential crashes under certain network driver states.
        await Task.Run(() =>
        {
            // Adapters
            try
            {
                foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (nic.OperationalStatus != OperationalStatus.Up) continue;
                    var props = nic.GetIPProperties();
                    string ip = string.Empty;
                    foreach (var addr in props.UnicastAddresses)
                    {
                        if (addr.Address.AddressFamily == AddressFamily.InterNetwork)
                        { ip = addr.Address.ToString(); break; }
                    }
                    result.Adapters.Add(new NetworkAdapterInfo
                    {
                        Name       = nic.Name,
                        IpAddress  = ip,
                        MacAddress = nic.GetPhysicalAddress().ToString(),
                        Status     = nic.OperationalStatus.ToString(),
                        Speed      = nic.Speed > 0 ? $"{nic.Speed / 1_000_000} Mbps" : "Unknown"
                    });
                }
            }
            catch { }

            // Active TCP connections
            try
            {
                var props2 = IPGlobalProperties.GetIPGlobalProperties();
                foreach (var conn in props2.GetActiveTcpConnections())
                {
                    result.Connections.Add(new ActiveConnection
                    {
                        Protocol   = "TCP",
                        LocalPort  = conn.LocalEndPoint.Port.ToString(),
                        RemoteAddr = conn.RemoteEndPoint.Address.ToString(),
                        RemotePort = conn.RemoteEndPoint.Port.ToString(),
                        State      = conn.State.ToString()
                    });
                }
            }
            catch { }
        });

        // Public IP — async HTTP (no Task.Run needed)
        try
        {
            result.PublicIp = (await _http.GetStringAsync("https://api.ipify.org")).Trim();
        }
        catch { result.PublicIp = "Unavailable"; }

        return result;
    }
}

public sealed class NetworkScanResult
{
    public List<NetworkAdapterInfo> Adapters    { get; } = new();
    public List<ActiveConnection>   Connections { get; } = new();
    public string PublicIp    { get; set; } = "--";
    public long   DownloadBps { get; set; }
    public long   UploadBps   { get; set; }
}
