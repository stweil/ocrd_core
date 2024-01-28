"""
OCR-D CLI: Logging

.. click:: ocrd.cli.log:log_cli
    :prog: ocrd log
    :nested: full
"""
import logging

import click

from ocrd_utils import getLevelName, getLogger, initLogging


class LogCtx():

    def __init__(self, name):
        self.name = name

    def log(self, lvl, *args, **kwargs):
        logger = getLogger(self.name)
        logger.log(getLevelName(lvl), *args, **kwargs)

pass_log = click.make_pass_decorator(LogCtx)

@click.group("log")
@click.option('-n', '--name', envvar='OCRD_TOOL_NAME', default='log_cli', metavar='LOGGER_NAME', help='Name of the logger', show_default=True)
@click.pass_context
def log_cli(ctx, name, *args, **kwargs):
    """
    Logging

    Logger name will be ocrd.OCRD_TOOL_NAME where OCRD_TOOL_NAME is normally
    (when using bashlib) the name of the processor.
    """
    initLogging()
    ctx.obj = LogCtx('ocrd.' + name)

def _bind_log_command(lvl):
    @click.argument('msgs', nargs=-1)
    @pass_log
    def _log_wrapper(ctx, msgs):
        if not msgs:
            ctx.log(lvl.upper(), '')
        elif len(msgs) == 1 and msgs[0] == '-':
            for stdin_line in click.get_text_stream('stdin'):
                ctx.log(lvl.upper(), stdin_line.rstrip('\n'))
        else:
            msg = list(msgs) if '%s' in msgs[0] else ' '.join([x.replace('%', '%%') for x in msgs])
            ctx.log(lvl.upper(), msg)
    return _log_wrapper

for _lvl in ['trace', 'debug', 'info', 'warning', 'error', 'critical']:
    log_cli.command(_lvl, help="Log a %s message" % _lvl.upper())(_bind_log_command(_lvl))
