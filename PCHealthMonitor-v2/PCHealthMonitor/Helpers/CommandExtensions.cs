using System.Threading.Tasks;
using System.Windows.Input;

namespace PCHealthMonitor.Helpers;

public static class CommandExtensions
{
    /// <summary>
    /// Awaits an AsyncRelayCommand properly.
    /// For plain ICommand, fires Execute() and returns immediately.
    /// </summary>
    public static Task ExecuteAsync(this ICommand command, object? parameter = null)
    {
        if (!command.CanExecute(parameter))
            return Task.CompletedTask;

        if (command is AsyncRelayCommand arc)
            return arc.ExecuteAsync(parameter);

        command.Execute(parameter);
        return Task.CompletedTask;
    }
}
