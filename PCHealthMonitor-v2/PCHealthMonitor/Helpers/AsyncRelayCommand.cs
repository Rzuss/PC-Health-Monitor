using System;
using System.Threading.Tasks;
using System.Windows.Input;

namespace PCHealthMonitor.Helpers;

/// <summary>
/// Asynchronous ICommand — exposes ExecuteAsync for awaitable call-sites.
/// Prevents re-entrant execution while a task is running.
/// </summary>
public sealed class AsyncRelayCommand : ICommand
{
    private readonly Func<object?, Task> _execute;
    private readonly Func<object?, bool>? _canExecute;
    private bool _isExecuting;

    public AsyncRelayCommand(Func<object?, Task> execute, Func<object?, bool>? canExecute = null)
    {
        _execute    = execute ?? throw new ArgumentNullException(nameof(execute));
        _canExecute = canExecute;
    }

    /// <summary>Convenience constructor for parameterless async actions.</summary>
    public AsyncRelayCommand(Func<Task> execute, Func<bool>? canExecute = null)
        : this(_ => execute(), canExecute is null ? null : _ => canExecute())
    {
    }

    public event EventHandler? CanExecuteChanged
    {
        add    => CommandManager.RequerySuggested += value;
        remove => CommandManager.RequerySuggested -= value;
    }

    public bool CanExecute(object? parameter)
        => !_isExecuting && (_canExecute?.Invoke(parameter) ?? true);

    /// <summary>Fire-and-forget execution (required by ICommand interface).</summary>
    public async void Execute(object? parameter)
    {
        await ExecuteAsync(parameter);
    }

    /// <summary>Awaitable execution — use this from code-behind Loaded handlers.</summary>
    public async Task ExecuteAsync(object? parameter = null)
    {
        if (!CanExecute(parameter)) return;
        try
        {
            _isExecuting = true;
            CommandManager.InvalidateRequerySuggested();
            await _execute(parameter);
        }
        finally
        {
            _isExecuting = false;
            CommandManager.InvalidateRequerySuggested();
        }
    }

    public static void RaiseCanExecuteChanged() => CommandManager.InvalidateRequerySuggested();
}
