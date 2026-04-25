using System;

namespace PCHealthMonitor.Services;

/// <summary>
/// Lightweight event-bus for in-app toast notifications.
/// Call Show() from any service or ViewModel; MainWindow listens and
/// renders the toast overlay. Never blocks the UI thread.
/// </summary>
public sealed class ToastService
{
    // Raised on the calling thread — MainWindow marshals to Dispatcher.
    public event EventHandler<ToastMessage>? ToastRequested;

    // ── Public API ────────────────────────────────────────────────────────
    public void Show(string message, ToastType type = ToastType.Info, int durationMs = 4000)
        => ToastRequested?.Invoke(this, new ToastMessage(message, type, durationMs));

    public void Success(string message, int durationMs = 4000)
        => Show(message, ToastType.Success, durationMs);

    public void Warning(string message, int durationMs = 5000)
        => Show(message, ToastType.Warning, durationMs);

    public void Error(string message, int durationMs = 6000)
        => Show(message, ToastType.Error, durationMs);

    public void Info(string message, int durationMs = 4000)
        => Show(message, ToastType.Info, durationMs);
}

public enum ToastType { Success, Warning, Error, Info }

public sealed record ToastMessage(string Text, ToastType Type, int DurationMs);
