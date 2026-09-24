import 'package:aim_core/aim_core.dart';
import 'package:aim_schema/src/context.dart';
import 'package:aim_schema/src/responses.dart';
import 'package:aim_schema/src/schema.dart';

/// One request's already-validated data, as read by [typed] before the
/// handler ran.
///
/// A location that was not declared to [typed] (its schema was omitted)
/// reads as `null` here, typed as `Object?`.
final class TypedRequest<
  B extends Object?,
  Q extends Object?,
  P extends Object?
> {
  TypedRequest(this.body, this.query, this.path);

  /// The parsed request body, or `null` if [typed] was not given a `body`
  /// schema.
  final B body;

  /// The parsed query string, or `null` if [typed] was not given a `query`
  /// schema.
  final Q query;

  /// The parsed path parameters, or `null` if [typed] was not given a
  /// `path` schema.
  final P path;
}

/// A route handler that reads validated request data and returns a
/// [Reply] chosen from its own [Responses].
typedef TypedHandler<
  E extends Variables,
  B extends Object?,
  Q extends Object?,
  P extends Object?,
  R
> = Future<Reply> Function(Context<E> c, TypedRequest<B, Q, P> req, R res);

/// The request and response declarations [typed] attached to one handler,
/// for anything that reads a route's contract back — e.g. an OpenAPI
/// generator.
final class RouteContract {
  RouteContract(this.body, this.query, this.path, this.responses);

  /// The request body schema, or `null` if none was declared.
  final Schema<Object?>? body;

  /// The query schema, or `null` if none was declared.
  final Schema<Object?>? query;

  /// The path parameters schema, or `null` if none was declared.
  final Schema<Object?>? path;

  /// Every response this route can return, in declaration order — for
  /// reading back the declared statuses and [Output]s (e.g. to build an
  /// OpenAPI document), not for calling: an entry read from here has lost
  /// the static type [ResponseEntry.call] would otherwise check its
  /// argument against.
  final List<ResponseEntry<Object?>> responses;
}

final _contracts = Expando<RouteContract>();

/// The [RouteContract] [typed] attached to [handler], or `null` if
/// [handler] was not made by [typed].
///
/// Looks [handler] up by identity against the exact function [typed]
/// returned. Wrapping that function in another one — `(c) => handler(c)`,
/// a closure, a different `Handler` that merely calls it — produces a new
/// function the [Expando] has nothing recorded against, so the contract is
/// lost; keep and register the function [typed] itself returned.
RouteContract? routeContractOf(Function handler) => _contracts[handler];

/// Binds request schemas and a [Responses] declaration to a route.
///
/// Reads `path`, then `query`, then `body` — each optional; an omitted
/// location reads as `null` in the handler's [TypedRequest] — validates
/// them, and calls [handler] with the result and [responses]'s typed
/// entries. Any validation failure throws [ValidationException] before the
/// handler runs, the same as calling [SchemaContext.parse] /
/// [SchemaContext.parseQuery] directly.
///
/// The [Reply] [handler] returns is encoded and sent as JSON automatically.
Handler<E> typed<
  E extends Variables,
  B extends Object?,
  Q extends Object?,
  P extends Object?,
  R
>(
  TypedHandler<E, B, Q, P, R> handler, {
  Schema<B>? body,
  Schema<Q>? query,
  Schema<P>? path,
  required Responses<R> responses,
}) {
  Future<Response> handle(Context<E> c) async {
    P parsedPath;
    if (path != null) {
      final map = {
        for (final f in path.spec) f.name: ?c.get<String>('param:${f.name}'),
      };
      parsedPath = path.parse(map, coerce: true);
    } else {
      parsedPath = null as P;
    }

    Q parsedQuery;
    if (query != null) {
      parsedQuery = c.parseQuery(query);
    } else {
      parsedQuery = null as Q;
    }

    B parsedBody;
    if (body != null) {
      parsedBody = await c.parse(body);
    } else {
      parsedBody = null as B;
    }

    final req = TypedRequest<B, Q, P>(parsedBody, parsedQuery, parsedPath);
    final reply = await handler(c, req, responses.entries);
    return c.json(reply.body, statusCode: reply.status);
  }

  _contracts[handle] = RouteContract(body, query, path, responses.all);
  return handle;
}
