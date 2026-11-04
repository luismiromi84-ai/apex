require('dotenv').config();

const oracledb = require('oracledb');

console.log('Usuario cargado:', process.env.DB_USER);
console.log(
    'Contraseña cargada:',
    process.env.DB_PASSWORD ? 'SÍ' : 'NO'
);