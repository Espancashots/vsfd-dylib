UniversalIPAInspector — Inspetor UIKit/runtime

UniversalUIInspector.m é código-fonte Objective-C genérico para build com Xcode em macOS. Aguarda uma UIWindow utilizável sem bloquear o app, cria overlay read-only e exporta hierarquia/classes sob demanda para Application Support/UniversalUIInspector/.

O sandbox Linux não tem SDK iOS nem linker Apple; nenhum dylib falso é fornecido. Use .github/workflows/build-ios.yml ou o comando de build em README.md. Use somente em aplicações que você está autorizado a testar.
