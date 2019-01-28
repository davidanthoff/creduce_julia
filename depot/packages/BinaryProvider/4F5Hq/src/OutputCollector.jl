import Base: wait, merge
export OutputCollector, merge, collect_stdout, collect_stderr, tail, tee
struct LineStream
    pipe::Pipe
    lines::Vector{Tuple{Float64,String}}
    task::Task
end
""" """ function readuntil_many(s::IO, delims)
    out = IOBuffer()
    while !eof(s)
        c = read(s, Char)
        write(out, c)
        if c in delims
            break
        end
    end
    return String(take!(out))
end
""" """ function LineStream(pipe::Pipe, event::Condition)
    close(pipe.in)
    lines = Tuple{Float64,String}[]
    task = @async begin
        while true
            line = readuntil_many(pipe, ['\n', '\r'])
            if isempty(line) && eof(pipe)
                break
            end
            push!(lines, (time(), line))
            notify(event)
        end
    end
    @async begin
        fetch(task)
        notify(event)
    end
    return LineStream(pipe, lines, task)
end
""" """ function alive(s::LineStream)
    return !(s.task.state in [:done, :failed])
end
""" """ mutable struct OutputCollector
    cmd::Base.AbstractCmd
    P::Base.AbstractPipe
    stdout_linestream::LineStream
    stderr_linestream::LineStream
    event::Condition
    tee_stream::IO
    verbose::Bool
    tail_error::Bool
    done::Bool
    extra_tasks::Vector{Task}
    function OutputCollector(cmd, P, out_ls, err_ls, event, tee_stream,
                             verbose, tail_error)
        return new(cmd, P, out_ls, err_ls, event, tee_stream, verbose,
                   tail_error, false, Task[])
    end
end
""" """ function OutputCollector(cmd::Base.AbstractCmd; verbose::Bool=false,
                         tail_error::Bool=true, tee_stream::IO=stdout)
    out_pipe = Pipe()
    err_pipe = Pipe()
    P = try
        run(pipeline(cmd, stdin=devnull, stdout=out_pipe, stderr=err_pipe); wait=false)
    catch
        @warn("Could not spawn $(cmd)")
        rethrow()
    end
    event = Condition()
    out_ls = LineStream(out_pipe, event)
    err_ls = LineStream(err_pipe, event)
    self = OutputCollector(cmd, P, out_ls, err_ls, event, tee_stream,
                           verbose, tail_error)
    if verbose
        tee(self; stream = tee_stream)
    end
    return self
end
""" """ function wait(collector::OutputCollector)
    if !collector.done
        wait(collector.P)
        fetch(collector.stdout_linestream.task)
        fetch(collector.stderr_linestream.task)
        for t in collector.extra_tasks
            fetch(t)
        end
        collector.done = true
        if !success(collector.P) && !collector.verbose && collector.tail_error
            our_tail = tail(collector; colored=Base.have_color)
            print(collector.tee_stream, our_tail)
        end
    end
    return success(collector.P)
end
""" """ function merge(collector::OutputCollector; colored::Bool = false)
    wait(collector)
    stdout_lines = copy(collector.stdout_linestream.lines)
    stderr_lines = copy(collector.stderr_linestream.lines)
    output = IOBuffer()
    function write_line(lines, should_color, color)
        if should_color && colored
            print(output, color)
        end
        t, line = popfirst!(lines)
        print(output, line)
    end
    out_color = Base.text_colors[:default]
    err_color = Base.text_colors[:red]
    last_line_stderr = false
    while !isempty(stdout_lines) && !isempty(stderr_lines)
        if stdout_lines[1][1] < stderr_lines[1][1]
            write_line(stdout_lines,  last_line_stderr, out_color)
            last_line_stderr = false
        else
            write_line(stderr_lines, !last_line_stderr, err_color)
            last_line_stderr = true
        end
    end
    while !isempty(stdout_lines)
        write_line(stdout_lines, last_line_stderr, out_color)
        last_line_stderr = false
    end
    while !isempty(stderr_lines)
        write_line(stderr_lines, !last_line_stderr, err_color)
        last_line_stderr = true
    end
    if last_line_stderr && colored
        print(output, Base.text_colors[:default])
    end
    return String(take!(output))
end
""" """ function collect_stdout(collector::OutputCollector)
    return join([l[2] for l in collector.stdout_linestream.lines], "")
end
""" """ function collect_stderr(collector::OutputCollector)
    return join([l[2] for l in collector.stderr_linestream.lines], "")
end
""" """ function tail(collector::OutputCollector; len::Int = 100,
              colored::Bool = false)
    out = merge(collector; colored=colored)
    idx = length(out)
    for line_idx in 1:len
        try
            idx = findprev(isequal('\n'), out, idx-1)
            if idx === nothing || idx == 0
                idx = 0
                break
            end
        catch
            break
        end
    end
    return out[idx+1:end]
end
""" """ function tee(c::OutputCollector; colored::Bool=Base.have_color,
             stream::IO=stdout)
    tee_task = @async begin
        out_idx = 1
        err_idx = 1
        out_lines = c.stdout_linestream.lines
        err_lines = c.stderr_linestream.lines
        function print_next_line()
            timestr = Libc.strftime("[%T] ", time())
            printstyled(stream, timestr; bold=true)
            if length(out_lines) >= out_idx
                if length(err_lines) >= err_idx
                    if out_lines[out_idx][1] < err_lines[err_idx][1]
                        print(stream, out_lines[out_idx][2])
                        out_idx += 1
                    else
                        printstyled(stream, err_lines[err_idx][2]; color=:red)
                        print(stream)
                        err_idx += 1
                    end
                else
                    print(stream, out_lines[out_idx][2])
                    out_idx += 1
                end
            else
                printstyled(stream, err_lines[err_idx][2]; color=:red)
                print(stream)
                err_idx += 1
            end
        end
        wait(c.event)
        while alive(c.stdout_linestream) || alive(c.stderr_linestream)
            if length(out_lines) >= out_idx || length(err_lines) >= err_idx
                print_next_line()
            else
                wait(c.event)
            end
        end
        while length(out_lines) >= out_idx || length(err_lines) >= err_idx
            print_next_line()
        end
    end
    push!(c.extra_tasks, tee_task)
    return tee_task
end
