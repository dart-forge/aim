import 'package:aim_orm/aim_orm.dart';
import 'package:aim_orm_postgres/aim_orm_postgres.dart';
import 'package:aim_postgres/aim_postgres.dart';

part 'input.g.dart';

@PgTable('products')
final products = (
  id: serial('id').primaryKey(),
  name: varchar('name', length: 255),
  description: text('description').nullable(),
  price: integer('price').nullable(),
  status: varchar('status', length: 20).withDefault('draft'),
);
