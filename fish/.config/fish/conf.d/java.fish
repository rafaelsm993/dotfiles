# JAVA_HOME for the Salesforce apex-language-server (Mason JAR)
if command -q mise
    set -gx JAVA_HOME (mise where java 2>/dev/null)
end
