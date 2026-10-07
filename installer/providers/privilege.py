"""Privilege for the few steps that need it, never for the installer itself.

The UI and the engine run as the user. A package transaction is the only
root operation in a normal installation. It goes through polkit (pkexec)
when an authentication agent is running, otherwise through sudo on the
terminal that started the installer. With neither, the step refuses and
says what to do; nothing runs the installer under sudo.
"""


def method(host, facts):
    if host.which('pkexec') and facts.get('polkitAgent'):
        return 'pkexec'
    if host.which('sudo') and host.has_tty():
        return 'sudo'
    return ''


def describe(name):
    return {'pkexec': 'A system authentication prompt will ask for your password.',
            'sudo': 'The terminal that started the installer will ask for your password.',
            '': 'No way to ask for your password: start the installer from a terminal, or run a polkit authentication agent.'}[name]


def wrap(name, argv):
    if name == 'pkexec':
        return ['pkexec', *argv]
    if name == 'sudo':
        return ['sudo', '-p', 'CEDAR needs your password to install packages: ', *argv]
    raise RuntimeError(describe(''))


def method_name(facts):
    """The method the facts alone imply; the engine re-checks with the host before using it."""
    if facts.get('pkexec') and facts.get('polkitAgent'):
        return 'pkexec'
    if facts.get('sudo') and facts.get('tty'):
        return 'sudo'
    return ''
