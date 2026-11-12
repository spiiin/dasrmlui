options gen2
require dasrmlui/ui
[export]
def main(smoke:bool):int { let target=nav_to("#wrong"); return length(target.id) }
